#!/bin/bash

# =================
#
#
#
#
# legal_placeholder
#
#
#
# =================

## Variable via environment variable
LOG_RETENTION_HOURS=${LOG_RETENTION_HOURS:-365}
DIFF_RETENTION_HOURS=${DIFF_RETENTION_HOURS:-365}
NFS_PATH="${NFS_PATH:-/nfs}"
NFS_PATH="${NFS_PATH}/objectstore"
EXCLUDE_BUCKETS="${EXCLUDE_BUCKETS:-}"                 ## comma separated list
INCLUDE_BUCKETS="${INCLUDE_BUCKETS:-}"                 ## comma separated list
EXCLUDE_BUCKETS_PATTERN="${EXCLUDE_BUCKETS_PATTERN:-}" ## grep perl regex
INCLUDE_BUCKETS_PATTERN="${INCLUDE_BUCKETS_PATTERN:-}" ## grep perl regex
RESTORE_EPOCH="${RESTORE_EPOCH:-latest}"
RESTORE_EPOCH_ORDER="${RESTORE_EPOCH_ORDER:-latest}"
RESTORE_START_EPOCH="${RESTORE_START_EPOCH:-}"
RESTORE_END_EPOCH="${RESTORE_END_EPOCH:-}"
RESTORE_TEMP_PATH="${RESTORE_TEMP_PATH:-${NFS_PATH}/tmp}"
OP="${OP:-backup}"

set -e

function clean_up_old_dir() {
  local epoch_threshold="$1"
  local dst_dir="$2"
  local dir

  [[ ! -d $dst_dir ]] && return
  for dir in "$dst_dir"/*/; do
    dir=$(basename "$dir")
    if [[ -d ${dst_dir}/$dir && $dir -lt $epoch_threshold ]]; then
      echo "cleaning up ${dst_dir}/$dir"
      \rm -rf "${dst_dir:?}/${dir:?}"
    fi
  done
}

function hash_sha256 {
  # shellcheck disable=SC2059
  printf "${1}" | openssl dgst -sha256 | sed 's/^.* //'
}

function hmac_sha256 {
  # shellcheck disable=SC2059
  printf "${2}" | openssl dgst -sha256 -mac HMAC -macopt "${1}" | sed 's/^.* //'
}

function call_s3_api() {
  local command="$1"
  local url="$2"
  local file="${3:--}"
  local args=()
  local canonical_header
  local current_date date_iso8601 bucket_name
  local http_req_signed_header

  if [ "${url:0:5}" != "s3://" ]; then
    echo "Need an s3 url"
    return 1
  fi

  local path="${url:4}"
  local query_string=${path##*\?}
  local rook_url=rook-ceph-rgw-rook-ceph.rook-ceph.svc
  local payload payload_hash

  bucket_name=$(echo "$path" | cut -d '/' -f2)
  current_date="$(date -u '+%Y%m%d')"
  date_iso8601="${current_date}T$(date -u '+%H%M%S')Z"

  if [ -z "${AWS_ACCESS_KEY-}" ]; then
    echo "Need AWS_ACCESS_KEY to be set"
    return 1
  fi

  if [ -z "${AWS_SECRET_KEY-}" ]; then
    echo "Need AWS_SECRET_KEY to be set"
    return 1
  fi

  local method payload_hash args payload_md5_hash
  case "$command" in
  get)
    method="GET"
    args+=(-o "$file")
    ;;
  put)
    method="PUT"
    if [ ! -f "$file" ]; then
      echo "file not found"
      exit 1
    fi
    payload="$(cat "${file}")"
    args+=(-T "$file")
    ;;
  *)
    echo "Unsupported command"
    return 1
    ;;
  esac

  payload_hash="$(echo -n "${payload}" | openssl dgst -sha256 | sed 's/^.* //')"
  payload_md5_hash="$(echo -n "${payload}" | openssl dgst -md5 -binary | openssl enc -base64 | sed 's/^.* //')"
  http_req_signed_header="content-md5;host;x-amz-content-sha256;x-amz-date"
  canonical_header="content-md5:${payload_md5_hash}
host:${rook_url}
x-amz-content-sha256:${payload_hash}
x-amz-date:${date_iso8601}"

  local canonical_request

  canonical_request="$method
/${bucket_name}/
${query_string}
${canonical_header}

${http_req_signed_header}
${payload_hash}"

  local stringToSign dateKey regionKey serviceKey signingKey signature authorization
  stringToSign="AWS4-HMAC-SHA256\n${date_iso8601}\n${current_date}/rook-ceph/s3/aws4_request\n$(hash_sha256 "${canonical_request}")"
  dateKey=$(hmac_sha256 key:"AWS4${AWS_SECRET_KEY}" "${current_date}")
  regionKey=$(hmac_sha256 hexkey:"${dateKey}" "rook-ceph")
  serviceKey=$(hmac_sha256 hexkey:"${regionKey}" "s3")
  signingKey=$(hmac_sha256 hexkey:"${serviceKey}" "aws4_request")
  # shellcheck disable=SC2059
  signature=$(printf "${stringToSign}" | openssl dgst -sha256 -mac HMAC -macopt hexkey:"${signingKey}" | sed 's/(stdin)= //')

  authorization="\
AWS4-HMAC-SHA256 Credential=${AWS_ACCESS_KEY}/${current_date}/\
rook-ceph/s3/aws4_request, \
SignedHeaders=${http_req_signed_header}, Signature=${signature}"

  curl "${args[@]}" -s -f \
    "http://${rook_url}${path}" \
    -H "Authorization: ${authorization}" \
    -H "content-md5: ${payload_md5_hash}" \
    -H "x-amz-content-sha256: ${payload_hash}" \
    -H "x-amz-date: ${date_iso8601}"
}

function get_bucket_config() {
  local bucket_name="$1"
  local bucket_config="$2"
  bucket_config=$(call_s3_api "get" "s3://${bucket_name}/?${bucket_config}=")
  [[ -z $bucket_config ]] || echo "$bucket_config"
}

function put_bucket_config() {
  local bucket_name="$1"
  local bucket_config="$2"
  local data_file="$3"
  call_s3_api "put" "s3://${bucket_name}/?${bucket_config}=" "$data_file"
}

function restore_bucket_config() {
  local bucket_name="$1"
  local bucket_config="$2"
  local data_file="$3"
  local return_code=0

  echo "Restoring bucket: '${bucket_name}' ${bucket_config^^}"
  if put_bucket_config "${bucket_name}" "${bucket_config}" "${data_file}"; then
    echo "Successfully restored bucket: '${bucket}' ${bucket_config^^}"
  else
    echo "Failure while restoring bucket: '${bucket}' ${bucket_config^^}"
    return_code=1
  fi
  return "$return_code"
}

function get_bucket_owner() {
  local bucket_name="$1"
  local bucket_owner
  bucket_owner=$(kubectl --cache-dir /tmp -n rook-ceph exec deploy/rook-ceph-tools -- radosgw-admin bucket stats --bucket "${bucket}" | jq '.owner' -r)
  [[ -z $bucket_owner ]] || echo "$bucket_owner"
}

function configure_rclone() {
  local user cmd
  user=$1
  cmd="kubectl --cache-dir /tmp -n rook-ceph exec deploy/rook-ceph-tools -- radosgw-admin user info --uid=${user}  --format json"
  eval "$(${cmd} | jq -r '.keys[0] | { "RCLONE_CONFIG_CEPH_ACCESS_KEY_ID" : .access_key , "RCLONE_CONFIG_CEPH_SECRET_ACCESS_KEY": .secret_key } | to_entries[] | .key + "=" + (.value | @sh)')"
  export RCLONE_CONFIG_CEPH_ACCESS_KEY_ID
  export RCLONE_CONFIG_CEPH_SECRET_ACCESS_KEY
  export RCLONE_CONFIG_CEPH_TYPE=s3
  export RCLONE_CONFIG_CEPH_PROVIDER=Ceph
  export RCLONE_CONFIG_CEPH_ENDPOINT=http://rook-ceph-rgw-rook-ceph.rook-ceph.svc
  export RCLONE_CONFIG_CEPH_REGION=us-east-1
}

function configure_s3cmd() {
  export AWS_ACCESS_KEY=$RCLONE_CONFIG_CEPH_ACCESS_KEY_ID
  export AWS_SECRET_KEY=$RCLONE_CONFIG_CEPH_SECRET_ACCESS_KEY
}

function change_bucket_owner() {
  local bucket="$1"
  local user="$2"

  kubectl --cache-dir /tmp -n rook-ceph exec deploy/rook-ceph-tools -- radosgw-admin bucket link --uid "${user}" --bucket "${bucket}" || (echo "Failure running bucket link" && return 1)
  kubectl --cache-dir /tmp -n rook-ceph exec deploy/rook-ceph-tools -- radosgw-admin bucket chown --uid "${user}" --bucket "${bucket}" || (echo "Failure running bucket chown" && return 1)
}

function validate_epoch() {
  local epoch="$1"

  if ! date -d "@$epoch" >>/dev/null; then
    echo "Provide Valid value for restore epoch"
    exit 1
  fi
}

function validate_restore_epoch() {
  local epoch="$1"

  validate_epoch "${epoch}"

  if [[ ! -d "${DIFF_DIR}/${epoch}" ]]; then
    echo "Provided epoch value: '${epoch}' does not match with any of the available backup"
    find "$DIFF_DIR" -maxdepth 1 -mindepth 1 -type d -print0 | xargs -0 -I{} basename {}
    exit 1
  fi
}

function prepare_pitr_restore() {
  local bucket="$1"
  local restore_path="${RESTORE_TEMP_PATH}/${bucket}"

  rm -rf "${restore_path}"
  mkdir -p "${restore_path}"
  cp -r --preserve=timestamps "${DST_DIR}/${bucket}/." "${restore_path}"

  for diff_dir in $(find "$DIFF_DIR" -maxdepth 1 -mindepth 1 -type d -newermt "@${RESTORE_EPOCH}" | sort -r | sed '$ d'); do
    if [[ -d "${diff_dir}/${bucket}" ]]; then
      cp -r --preserve=timestamps "${diff_dir}/${bucket}/." "${restore_path}"
    fi
  done

  find "${restore_path}" -newermt "@${RESTORE_EPOCH}" -type f -print0 | xargs -0 -r rm -f
}

function find_restore_epoch() {
  local restore_start_epoch="$1"
  local restore_end_epoch="$2"
  local restore_epoch_order="$3"
  local eligible_epochs
  local eligible_epochs_json

  eligible_epochs=$(find "$DIFF_DIR" -maxdepth 1 -mindepth 1 -type d -print0 | xargs -r -0 -I{} basename {} | tr '\n' ',' | sed 's/,$//g')
  if [[ -z "${eligible_epochs}" ]]; then
    echo "Unable to find backup created between provided start epoch('${restore_start_epoch}') and end epoch('${restore_end_epoch}')"
    exit 1
  fi
  eligible_epochs_json=$(jq -c -n --arg epochs "${eligible_epochs}" '[$epochs | split(",") | .[] | gsub("^\\s+|\\s+$";"") | tonumber]')
  jq -n --argjson epochs "${eligible_epochs_json}" --arg startEpoch "${restore_start_epoch}" --arg endEpoch "${restore_end_epoch}" --arg epochOrder "${restore_epoch_order}" '[$epochs[] | select(. > ($startEpoch | tonumber) and . < ($endEpoch | tonumber))] | sort | if $epochOrder == "latest" then .[-1] else .[0] end'
}

function is_cephobjectstore_present() {
  local return_code=1
  if kubectl --cache-dir /tmp -n rook-ceph get cephobjectstore rook-ceph >>/dev/null; then
    return_code=0
  fi
  return "${return_code}"
}

function main() {
  is_cephobjectstore_present || exit 0
  EPOCH=$(date +"%s")
  BACKUP_DIR="${NFS_PATH}/backup/s3"
  LOG_DIR="${BACKUP_DIR}/logs"
  LOG_FILE="${LOG_DIR}/${EPOCH}/backup.log"
  DIFF_DIR="${BACKUP_DIR}/diff"
  DST_DIR="${BACKUP_DIR}/latest"
  EXCLUDE_BUCKETS_ARRAY=$(jq -c -n --arg buckets "${EXCLUDE_BUCKETS}" '[$buckets | split(",") | .[] | gsub("^\\s+|\\s+$";"")]')
  INCLUDE_BUCKETS_ARRAY=$(jq -c -n --arg buckets "${INCLUDE_BUCKETS}" '[$buckets | split(",") | .[] | gsub("^\\s+|\\s+$";"")]')
  configure_rclone "admin"
  configure_s3cmd
  case "$OP" in
  backup)
    buckets=$(kubectl --cache-dir /tmp -n rook-ceph exec deploy/rook-ceph-tools -- radosgw-admin bucket list --format json | jq -r '.[]')
    ;;
  restore)
    if [[ $RESTORE_EPOCH != "latest" ]]; then
      validate_restore_epoch "$RESTORE_EPOCH"
    elif [[ -n "$RESTORE_START_EPOCH" || -n "${RESTORE_END_EPOCH}" ]]; then
      echo "Validating Provided start epoch: '${RESTORE_START_EPOCH}'"
      validate_epoch "${RESTORE_START_EPOCH}"
      echo "Validating Provided end epoch: '${RESTORE_END_EPOCH}'"
      validate_epoch "${RESTORE_END_EPOCH}"
      if [[ "$RESTORE_END_EPOCH" -le "${RESTORE_START_EPOCH}" ]]; then
        echo "End epoch('${RESTORE_END_EPOCH}') must be greater than start epoch('${RESTORE_START_EPOCH}')"
        exit 1
      fi
      RESTORE_EPOCH=$(find_restore_epoch "${RESTORE_START_EPOCH}" "${RESTORE_END_EPOCH}" "${RESTORE_EPOCH_ORDER}")
      echo "Validating discovered epoch: '${RESTORE_EPOCH}'"
      validate_restore_epoch "$RESTORE_EPOCH"
    fi
    if [[ -d $DST_DIR ]]; then
      buckets=$(find "$DST_DIR" -maxdepth 1 -mindepth 1 -type d -print0 | xargs -0 -I{} basename {})
      if [[ -n $buckets ]]; then
        LOG_FILE="${NFS_PATH}/restore/s3/logs/${EPOCH}/restore.log"
      fi
    else
      echo "Backup path not found at '${DST_DIR}'"
      exit 1
    fi
    ;;
  *)
    echo "Unsupported value: '$OP' for operation"
    exit 1
    ;;
  esac

  if [[ -z $buckets ]]; then
    echo "Bucket list is empty, cannot perform ${OP}"
    exit 1
  fi

  mkdir -p "$(dirname "${LOG_FILE}")"
  [[ $OP == "backup" ]] && mkdir -p "${DIFF_DIR}/${EPOCH}"
  echo "Using file: '${LOG_FILE}' for storing logs"
  tail -F "${LOG_FILE}" 2>/dev/null &
  logs_tail_pid="$!"
  op_pid=()
  for bucket in $buckets; do
    include_bucket='false'
    if [[ -n $INCLUDE_BUCKETS_PATTERN ]] && echo "${bucket}" | grep -q -P "$INCLUDE_BUCKETS_PATTERN"; then
      include_bucket='true'
    fi

    if [[ $INCLUDE_BUCKETS_ARRAY != '[]' ]]; then
      if ! jq -n --argjson includeList "${INCLUDE_BUCKETS_ARRAY}" --arg bucket "$bucket" '$includeList | index($bucket)' | grep -q 'null'; then
        include_bucket='true'
      fi
    fi

    if [[ -n $INCLUDE_BUCKETS_PATTERN || $INCLUDE_BUCKETS_ARRAY != '[]' ]] && [[ $include_bucket == "false" ]]; then
      echo "Skipping ${OP} for bucket: '${bucket}' Not Found in include list or include pattern"
      continue
    fi

    if ! jq -n --argjson excludeList "${EXCLUDE_BUCKETS_ARRAY}" --arg bucket "$bucket" '$excludeList | index($bucket)' | grep -q 'null'; then
      echo "Skipping ${OP} for bucket: '${bucket}' Found in exclude list"
      continue
    fi
    if [[ -n $EXCLUDE_BUCKETS_PATTERN ]] && echo "${bucket}" | grep -q -P "$EXCLUDE_BUCKETS_PATTERN"; then
      echo "Skipping ${OP} for bucket: '${bucket}' Matching exclude pattern"
      continue
    fi

    echo "Running ${OP} for bucket: '${bucket}'"
    owner_file="${BACKUP_DIR}/info/${bucket}/owner.txt"
    cors_file="${BACKUP_DIR}/info/${bucket}/cors.xml"
    policy_file="${BACKUP_DIR}/info/${bucket}/policy.json"
    acl_file="${BACKUP_DIR}/info/${bucket}/acl.xml"
    lifecycle_file="${BACKUP_DIR}/info/${bucket}/lifecycle.xml"
    if [[ $OP == "backup" ]]; then
      mkdir -p "$(dirname "${owner_file}")"

      bucket_owner=$(get_bucket_owner "${bucket}")
      [[ -n "$bucket_owner" ]] && echo "${bucket_owner}" >"$owner_file"
      [[ -z "$bucket_owner" ]] && echo "Unable to get owner of the bucket: '${bucket}'"

      bucket_cors=$(get_bucket_config "${bucket}" "cors")
      [[ -n "$bucket_cors" ]] && echo -n "${bucket_cors}" >"$cors_file"
      [[ -z "$bucket_cors" ]] && echo "No CORS found for bucket: '${bucket}'"

      bucket_policy=$(get_bucket_config "${bucket}" "policy")
      [[ -n "$bucket_policy" ]] && echo -n "${bucket_policy}" >"$policy_file"
      [[ -z "$bucket_policy" ]] && echo "No bucket policy found for bucket: '${bucket}'"

      bucket_acl=$(get_bucket_config "${bucket}" "acl")
      [[ -n "$bucket_acl" ]] && echo -n "${bucket_acl}" >"$acl_file"
      [[ -z "$bucket_acl" ]] && echo "No ACL found for bucket: '${bucket}'"

      bucket_lifecycle=$(get_bucket_config "${bucket}" "lifecycle")
      [[ -n "$bucket_lifecycle" ]] && echo -n "${bucket_lifecycle}" >"$lifecycle_file"
      [[ -z "$bucket_lifecycle" ]] && echo "No Lifecycle policy found for bucket: '${bucket}'"
      # Actual Backup step
      rclone sync "ceph:${bucket}" "${DST_DIR}/${bucket}" --stats=0 --backup-dir "${DIFF_DIR}/${EPOCH}/${bucket}" --log-level INFO --log-file "$LOG_FILE" --ignore-checksum --ignore-errors &
      op_pid+=("${bucket}=$!")
    fi

    if [[ $OP == "restore" ]]; then
      restore_src="${DST_DIR}/${bucket}"
      owner_file="${BACKUP_DIR}/info/${bucket}/owner.txt"
      owner="admin"
      [[ -f "$owner_file" && -s "$owner_file" ]] && owner=$(cat "$owner_file")
      configure_rclone "${owner}"
      configure_s3cmd

      if [[ $RESTORE_EPOCH != "latest" ]]; then
        prepare_pitr_restore "${bucket}"
        restore_src="${RESTORE_TEMP_PATH}/${bucket}"
      fi
      rclone sync "${restore_src}" "ceph:${bucket}" --stats=0 --log-level INFO --log-file "$LOG_FILE" &
      op_pid+=("${bucket}=$!")
    fi
  done

  exit_code=0
  for pid in "${op_pid[@]}"; do
    bucket=$(echo "$pid" | cut -d'=' -f1)
    cpid=$(echo "$pid" | cut -d'=' -f2)
    owner_file="${BACKUP_DIR}/info/${bucket}/owner.txt"
    cors_file="${BACKUP_DIR}/info/${bucket}/cors.xml"
    policy_file="${BACKUP_DIR}/info/${bucket}/policy.json"
    acl_file="${BACKUP_DIR}/info/${bucket}/acl.xml"
    lifecycle_file="${BACKUP_DIR}/info/${bucket}/lifecycle.xml"
    if ! wait "$cpid"; then
      echo "Failure running ${OP} for bucket '${bucket}'"
      exit_code=1
    else
      if [[ $OP == "restore" ]]; then
        owner="admin"
        [[ -f "$owner_file" && -s "$owner_file" ]] && owner=$(cat "$owner_file")
        configure_rclone "${owner}"
        configure_s3cmd

        # Restore ACL
        if [[ -f "$acl_file" && -s "$acl_file" ]]; then
          restore_bucket_config "${bucket}" "acl" "$acl_file" || exit_code=1
        else
          echo "Skipping ACL restore for bucket: '${bucket}' as ACL config not found in backup"
        fi

        # Restore CORS
        if [[ -f "$cors_file" && -s "$cors_file" ]]; then
          restore_bucket_config "${bucket}" "cors" "$cors_file" || exit_code=1
        else
          echo "Skipping CORS restore for bucket: '${bucket}' as CORS config not found in backup"
        fi

        # Restore bucket policy
        if [[ -f "$policy_file" && -s "$policy_file" ]]; then
          restore_bucket_config "${bucket}" "policy" "$policy_file" || exit_code=1
        else
          echo "Skipping Policy restore for bucket: '${bucket}' as Policy config not found in backup"
        fi

        # Restore lifecycle policy
        if [[ -f "$lifecycle_file" && -s "$lifecycle_file" ]]; then
          restore_bucket_config "${bucket}" "lifecycle" "$lifecycle_file" || exit_code=1
        else
          echo "Skipping Lifecycle Policy restore for bucket: '${bucket}' as Lifecycle Policy config not found in backup"
        fi
      fi
    fi
  done

  [[ $OP == "restore" ]] && rm -rf "${RESTORE_TEMP_PATH}"
  log_epoch=$(date -d "$LOG_RETENTION_HOURS hours ago" +"%s")
  diff_epoch=$(date -d "$DIFF_RETENTION_HOURS hours ago" +"%s")
  [[ $exit_code -eq 0 && $OP == "backup" ]] && clean_up_old_dir "$log_epoch" "$LOG_DIR"
  [[ $exit_code -eq 0 && $OP == "backup" ]] && clean_up_old_dir "$diff_epoch" "$DIFF_DIR"
  kill -9 "$logs_tail_pid"
  wait "$logs_tail_pid" 2>/dev/null || true
  [[ $exit_code -eq 0 ]] && echo "$(date +'%Y-%m-%d %H:%M:%S') S3 bucket ${OP} completed successfully"
  return $exit_code
}

main
