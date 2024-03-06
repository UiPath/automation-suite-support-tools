#!/bin/bash


export PATH="$PATH:/usr/local/bin:/var/lib/rancher/rke2/bin"
export KUBECONFIG="/etc/rancher/rke2/rke2.yaml"


execute_command() {
    echo "Executing: $1"
    
    # Create temporary files for stdout and stderr
    TMP_OUT=$(mktemp)
    TMP_ERR=$(mktemp)

    # Execute command and redirect outputs to temporary files
    eval "$1" > "$TMP_OUT" 2> "$TMP_ERR"
    CMD_EXIT_CODE=$?

    # Capture outputs from temporary files into the variables
    CMD_OUT=$(cat "$TMP_OUT")
    CMD_ERR=$(cat "$TMP_ERR")

    # Cleanup temporary files
    rm -f "$TMP_OUT" "$TMP_ERR"

}

test_tmp_write_access() {
    echo "Testing write access to /tmp"
    # Create a temporary file in /tmp
    TMP_FILE="/tmp/test_write_access_$(date +%s%N).tmp"

    # Try to write to the temporary file
    if echo "test" > "$TMP_FILE"; then
        echo "Write access to /tmp confirmed."
        # Cleanup the test file
        rm -f "$TMP_FILE"
    else
        echo "Failed to write to /tmp."
        exit 1
    fi

    echo ""
}

cleanup() {
    echo "Failure occurred. Scaling backup rabbitmq as a precaution"
    cmd=" kubectl -n rabbitmq patch rabbitmqcluster rabbitmq -p \"{\\\"spec\\\":{\\\"replicas\\\": $rabbitmqReplicas}}\" --type=merge"
    execute_command "$cmd"

    if [ "$CMD_EXIT_CODE" -ne 0 ]; then
        echo "Failed to patch rabbitmq replicas"
        echo "ERROR: $CMD_ERR"
        echo "Try manually running the following command: $cmd"
        exit 1
    fi

    echo "Rabbitmq is scaled called back up. Address the error that caused the exit and try re-running the script"
}

cleanup_post_secretDeletion() {
    echo "-Failure occurred post successful secret deletion. See error for more details"
    echo "--------IMPORTANT--------"
    echo "At this point, try logging in to argocd and syncing sfcore (if on 21.10.X or 22.4.X) and UiPath (applies to all versions)"
    echo "Credentials manager must recreate the secrets for rabbitmq before this script can be executed again"
    exit 1

}

set_replicas() {
    echo "Getting and saving rabbitmq replicas count"
    cmd=" kubectl -n rabbitmq get rabbitmqcluster rabbitmq -o json | jq -r '.spec.replicas'"
    execute_command "$cmd"

    if [ "$CMD_EXIT_CODE" -ne 0 ]; then
        echo "Failed to get rabbitmq replicas"
        echo "ERROR: $CMD_ERR"
        exit 1
    fi

    echo "Replica Count: $CMD_OUT"
    echo ""

    rabbitmqReplicas=$CMD_OUT
}

patch_rabbitmq_cluster() {
    echo "Patching rabbitmq replicas to $1"
    cmd=" kubectl -n rabbitmq patch rabbitmqcluster rabbitmq -p \"{\\\"spec\\\":{\\\"replicas\\\": $1}}\" --type=merge"
    execute_command "$cmd"

    if [ "$CMD_EXIT_CODE" -ne 0 ]; then
        echo "Failed to patch rabbitmq replicas"
        echo "ERROR: $CMD_ERR"
        exit 1
    fi

    echo ""
}

scale_down_rabbitmq_sts () {
    echo "Scaling down rabbitmq sts to 0"
    cmd=" kubectl -n rabbitmq scale sts rabbitmq-server --replicas=0"
    execute_command "$cmd"

    if [ "$CMD_EXIT_CODE" -ne 0 ]; then
        echo "Failed to scale down rabbitmq sts"
        echo "ERROR: $CMD_ERR"
        exit 1
    fi

    echo "Force deleting rabbitmq pods"
    cmd=" kubectl -n rabbitmq delete pods --all --force --grace-period=0"
    execute_command "$cmd"

    if [ "$CMD_EXIT_CODE" -ne 0 ]; then
        echo "Failed to delete rabbitmq pods"
        echo "ERROR: $CMD_ERR"
        exit 1
    fi

    echo ""
}

delete_pvcs () {
    echo "Deleting rabbitmq pvc(s)"
    cmd=" kubectl -n rabbitmq delete pvc --all --force --grace-period=0"
    execute_command "$cmd"

    if [ "$CMD_EXIT_CODE" -ne 0 ]; then
        echo "Failed to delete rabbitmq pvc"
        echo "ERROR: $CMD_ERR"
        exit 1
    fi

    echo ""
}


#
#    Secret should be deleted by a hook. But if it fails, we need to delete it manually.
#
delete_uipath_secret () {
    echo "Deleting uipath secret"
    cmd=" kubectl -n uipath get secret --template '{{range .items}}{{.metadata.name}}{{\"\\n\"}}{{end}}' | grep -i rabbitmq-secret | xargs -I{} kubectl -n uipath delete secret {}"
    execute_command "$cmd"

    if [ "$CMD_EXIT_CODE" -ne 0 ]; then
        echo "Failed to delete uipath secret"
        echo "ERROR: $CMD_ERR"
        echo "Its OK to ignore this"
    fi

    echo ""
}

delete_rabbitmq_secret () {
    echo "Deleting rabbitmq secret"
    cmd=" kubectl -n rabbitmq get secret --template '{{range .items}}{{.metadata.name}}{{\"\\n\"}}{{end}}' | grep -i rabbitmq-secret | xargs -I{} kubectl -n rabbitmq delete secret {}"
    execute_command "$cmd"

    if [ "$CMD_EXIT_CODE" -ne 0 ]; then
        echo "Failed to delete rabbitmq secret"
        echo "ERROR: $CMD_ERR"
        exit 1
    fi
    echo ""
}

find_argocd () {
    echo "Finding argocd binary"
    cmd=" find /opt/UiPathAutomationSuite -type f -name argocd"
    execute_command "$cmd"

    if [ "$CMD_EXIT_CODE" -ne 0 ]; then
        echo "Failed to find argocd pod"
        echo "ERROR: $CMD_ERR"
        exit 1
    fi
    local files=$CMD_OUT

    if [[ ! $files ]]; then
        echo "No argocd binary found."
        echo "Try manually syncing UiPath from the argocd UI"
        exit 1
    fi

    argocd=$(ls -t $files | head -n 1)
    
    echo "Latest argocd binary: $argocd"
    echo ""

}

login_argocd () {
    echo "Logging into argocd"

    echo "Get the argocd server ip"
    cmd=" kubectl -n istio-system get vs argocdserver-vs  -o jsonpath='{.spec.hosts[0]}'"
    execute_command "$cmd"

    if [ "$CMD_EXIT_CODE" -ne 0 ]; then
        echo "Failed to get argocd server ip"
        echo "ERROR: $CMD_ERR"
        exit 1
    fi

    local argocdServerIp=$CMD_OUT
    echo "Argocd Server IP: $argocdServerIp"

    echo "Get the argocd admin password"
    cmd=" kubectl get secrets/argocd-admin-password -n argocd -o jsonpath='{.data.password}'"
    execute_command "$cmd"

    if [ "$CMD_EXIT_CODE" -ne 0 ]; then
        echo "Failed to get argocd admin password"
        echo "ERROR: $CMD_ERR"
        exit 1
    fi

    local argocdAdminPassword=$(echo $CMD_OUT | base64 -d)
    echo "Argocd Admin Password: $argocdAdminPassword"
    cmd=" $argocd login $argocdServerIp:443 --username admin --password $argocdAdminPassword  --grpc-web --grpc-web-root-path "/" --insecure"
    execute_command "$cmd"

    if [ "$CMD_EXIT_CODE" -ne 0 ]; then
        echo "Failed to login to argocd"
        echo "ERROR: $CMD_ERR"
        exit 1
    fi
    echo ""
}

sync_argocd_apps () {
    echo "Syncing argocd app(s) - This may take some time - The status in argocd UI will be more interesting to watch"

    echo "Checking Version"
    cmd=" kubectl -n argocd get applications orchestrator -o jsonpath={.spec.source.targetRevision}"
    execute_command "$cmd"
    if [ "$CMD_EXIT_CODE" -ne 0 ]; then
        echo "Failed to determine version"
        echo "ERROR: $CMD_ERR"
        exit 1
    fi

    local version=$CMD_OUT
    
    #check to see if the version contains 21.10
    if [[ $version == *"21.10"* ]] || [[ $version == *"22.4"* ]]; then
        echo "Version is 21.10 or 22.4"
        echo "Syncing sfcore"
        cmd=" $argocd app sync sfcore"
        execute_command "$cmd"

        if [ "$CMD_EXIT_CODE" -ne 0 ]; then
            echo "Failed to resync sfcore argocd app"
            echo "ERROR: $CMD_ERR"
            zecho "If failure occured because sync is already in progress, ignore"
            exit 1
        fi
        echo ""
    fi

    cmd=" $argocd app sync uipath"
    execute_command "$cmd"

    if [ "$CMD_EXIT_CODE" -ne 0 ]; then
        echo "Failed to resync uipath argocd app"
        echo "ERROR: $CMD_ERR"
        echo "If failure occured because sync is already in progress, ignore"
        exit 1
    fi
    echo ""
}

##############################################################################################################
#  Main
##############################################################################################################


#
#   Check that we have access to tmp so our error handling works.
#
test_tmp_write_access
set_replicas
patch_rabbitmq_cluster 0 

#
# if this section fails, we should scale back up rabbitmq as a precaution
#
trap cleanup EXIT
scale_down_rabbitmq_sts "$rabbitmqReplicas"
delete_pvcs
trap - EXIT
patch_rabbitmq_cluster $rabbitmqReplicas

delete_rabbitmq_secret
# If a failure happens after a delete, they need to run a sync from the UI.
trap cleanup_post_secretDeletion EXIT
delete_uipath_secret
find_argocd
login_argocd
trap - EXIT

sync_argocd_apps


