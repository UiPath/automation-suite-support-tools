"use strict";(self.webpackChunkdocs_website=self.webpackChunkdocs_website||[]).push([[998],{3807:(e,r,n)=>{n.r(r),n.d(r,{assets:()=>i,contentTitle:()=>t,default:()=>h,frontMatter:()=>c,metadata:()=>l,toc:()=>o});var s=n(5893),a=n(1151);const c={sidebar_position:1},t="AS Cheat Sheet",l={id:"commands/as-cheat-sheet",title:"AS Cheat Sheet",description:"Glossary of frequently used commands",source:"@site/docs/commands/as-cheat-sheet.md",sourceDirName:"commands",slug:"/commands/as-cheat-sheet",permalink:"/automation-suite-support-tools/docs/commands/as-cheat-sheet",draft:!1,unlisted:!1,editUrl:"https://github.com/facebook/docusaurus/tree/main/packages/create-docusaurus/templates/shared/docs/commands/as-cheat-sheet.md",tags:[],version:"current",sidebarPosition:1,frontMatter:{sidebar_position:1},sidebar:"tutorialSidebar",next:{title:"Networking Commands",permalink:"/automation-suite-support-tools/docs/commands/networking-commands"}},i={},o=[{value:"Set kubecontext",id:"set-kubecontext",level:2},{value:"RKE2 Config File Locations",id:"rke2-config-file-locations",level:2},{value:"RKE2 Server",id:"rke2-server",level:2},{value:"Containerd",id:"containerd",level:2},{value:"Kubelet",id:"kubelet",level:2},{value:"etcd",id:"etcd",level:2},{value:"Kubernetes Events",id:"kubernetes-events",level:2},{value:"Mount Points",id:"mount-points",level:2},{value:"Kubelet Configuration",id:"kubelet-configuration",level:2},{value:"Service",id:"service",level:2},{value:"ArgoCD",id:"argocd",level:2},{value:"RabbitMQ",id:"rabbitmq",level:2},{value:"PriorityClass",id:"priorityclass",level:2},{value:"Images",id:"images",level:2},{value:"Pods",id:"pods",level:2}];function d(e){const r={code:"code",h1:"h1",h2:"h2",li:"li",ol:"ol",p:"p",pre:"pre",...(0,a.a)(),...e.components};return(0,s.jsxs)(s.Fragment,{children:[(0,s.jsx)(r.h1,{id:"as-cheat-sheet",children:"AS Cheat Sheet"}),"\n",(0,s.jsx)(r.p,{children:"Glossary of frequently used commands"}),"\n",(0,s.jsx)(r.h2,{id:"set-kubecontext",children:"Set kubecontext"}),"\n",(0,s.jsx)(r.pre,{children:(0,s.jsx)(r.code,{className:"language-bash",children:"export KUBECONFIG=/etc/rancher/rke2/rke2.yaml PATH=$PATH:/var/lib/rancher/rke2/bin:/usr/local/bin\n"})}),"\n",(0,s.jsx)(r.p,{children:"On Agent Nodes:"}),"\n",(0,s.jsx)(r.pre,{children:(0,s.jsx)(r.code,{className:"language-bash",children:"export KUBECONFIG=/var/lib/rancher/rke2/agent/kubelet.kubeconfig PATH=$PATH:/var/lib/rancher/rke2/bin:/usr/local/bin\n"})}),"\n",(0,s.jsx)(r.h2,{id:"rke2-config-file-locations",children:"RKE2 Config File Locations"}),"\n",(0,s.jsx)(r.pre,{children:(0,s.jsx)(r.code,{className:"language-bash",children:"cat /etc/rancher/rke2/config.yaml\nls /etc/rancher/rke2/rke2.yaml\n"})}),"\n",(0,s.jsx)(r.h2,{id:"rke2-server",children:"RKE2 Server"}),"\n",(0,s.jsx)(r.p,{children:"Restart RKE2 Server:"}),"\n",(0,s.jsx)(r.pre,{children:(0,s.jsx)(r.code,{className:"language-bash",children:"systemctl restart rke2-server\nor\nsystemctl stop rke2-server\nsystemctl start rke2-server\n"})}),"\n",(0,s.jsx)(r.p,{children:"RKE2 Server Status:"}),"\n",(0,s.jsx)(r.pre,{children:(0,s.jsx)(r.code,{className:"language-bash",children:"systemctl status rke2-server\n"})}),"\n",(0,s.jsx)(r.p,{children:"Follow RKE2 Server Logs:"}),"\n",(0,s.jsx)(r.pre,{children:(0,s.jsx)(r.code,{className:"language-bash",children:"journalctl -f -u rke2-server\n"})}),"\n",(0,s.jsx)(r.p,{children:"RKE2 Server Restart count:"}),"\n",(0,s.jsx)(r.pre,{children:(0,s.jsx)(r.code,{className:"language-bash",children:"systemctl show rke2-server -p NRestarts\njournalctl -u rke2-server | grep -i fatal | wc -l\n"})}),"\n",(0,s.jsx)(r.h2,{id:"containerd",children:"Containerd"}),"\n",(0,s.jsx)(r.p,{children:"List Containers using ctr:"}),"\n",(0,s.jsx)(r.pre,{children:(0,s.jsx)(r.code,{className:"language-bash",children:"/var/lib/rancher/rke2/bin/ctr --address /run/k3s/containerd/containerd.sock --namespace k8s.io container ls\n"})}),"\n",(0,s.jsx)(r.p,{children:"List Images using ctr:"}),"\n",(0,s.jsx)(r.pre,{children:(0,s.jsx)(r.code,{className:"language-bash",children:"/var/lib/rancher/rke2/bin/ctr --address /run/k3s/containerd/containerd.sock --namespace k8s.io images ls -q\n"})}),"\n",(0,s.jsx)(r.p,{children:"Containerd logs:"}),"\n",(0,s.jsx)(r.pre,{children:(0,s.jsx)(r.code,{className:"language-bash",children:"tail -f /var/lib/rancher/rke2/agent/containerd/containerd.log\n"})}),"\n",(0,s.jsx)(r.p,{children:"Containerd images location:"}),"\n",(0,s.jsx)(r.pre,{children:(0,s.jsx)(r.code,{className:"language-bash",children:"du -sh /var/lib/rancher/rke2/agent/containerd/io.containerd.snapshotter.v1.overlayfs/snapshots\n"})}),"\n",(0,s.jsx)(r.h2,{id:"kubelet",children:"Kubelet"}),"\n",(0,s.jsx)(r.p,{children:"Kubelet logs:"}),"\n",(0,s.jsx)(r.pre,{children:(0,s.jsx)(r.code,{className:"language-bash",children:"tail -f /var/lib/rancher/rke2/agent/logs/kubelet.log\n"})}),"\n",(0,s.jsx)(r.h2,{id:"etcd",children:"etcd"}),"\n",(0,s.jsx)(r.pre,{children:(0,s.jsx)(r.code,{className:"language-bash",children:"export CRI_CONFIG_FILE=/var/lib/rancher/rke2/agent/etc/crictl.yaml\netcdcontainer=$(/var/lib/rancher/rke2/bin/crictl ps --label io.kubernetes.container.name=etcd --quiet)\n"})}),"\n",(0,s.jsx)(r.p,{children:"etcd check perf:"}),"\n",(0,s.jsx)(r.pre,{children:(0,s.jsx)(r.code,{className:"language-bash",children:"export CRI_CONFIG_FILE=/var/lib/rancher/rke2/agent/etc/crictl.yaml\netcdcontainer=$(/var/lib/rancher/rke2/bin/crictl ps --label io.kubernetes.container.name=etcd --quiet)\n/var/lib/rancher/rke2/bin/crictl exec $etcdcontainer sh -c \"ETCDCTL_ENDPOINTS='https://127.0.0.1:2379' ETCDCTL_CACERT='/var/lib/rancher/rke2/server/tls/etcd/server-ca.crt' ETCDCTL_CERT='/var/lib/rancher/rke2/server/tls/etcd/server-client.crt' ETCDCTL_KEY='/var/lib/rancher/rke2/server/tls/etcd/server-client.key' ETCDCTL_API=3 etcdctl check perf\"\n"})}),"\n",(0,s.jsx)(r.p,{children:"etcdctl endpoint status:"}),"\n",(0,s.jsx)(r.pre,{children:(0,s.jsx)(r.code,{className:"language-bash",children:"export CRI_CONFIG_FILE=/var/lib/rancher/rke2/agent/etc/crictl.yaml\netcdcontainer=$(/var/lib/rancher/rke2/bin/crictl ps --label io.kubernetes.container.name=etcd --quiet)\n/var/lib/rancher/rke2/bin/crictl exec $etcdcontainer sh -c \"ETCDCTL_ENDPOINTS='https://127.0.0.1:2379' ETCDCTL_CACERT='/var/lib/rancher/rke2/server/tls/etcd/server-ca.crt' ETCDCTL_CERT='/var/lib/rancher/rke2/server/tls/etcd/server-client.crt' ETCDCTL_KEY='/var/lib/rancher/rke2/server/tls/etcd/server-client.key' ETCDCTL_API=3 etcdctl endpoint status --cluster --write-out=table\"\n"})}),"\n",(0,s.jsx)(r.p,{children:"etcdctl endpoint health:"}),"\n",(0,s.jsx)(r.pre,{children:(0,s.jsx)(r.code,{className:"language-bash",children:"export CRI_CONFIG_FILE=/var/lib/rancher/rke2/agent/etc/crictl.yaml\netcdcontainer=$(/var/lib/rancher/rke2/bin/crictl ps --label io.kubernetes.container.name=etcd --quiet)\n/var/lib/rancher/rke2/bin/crictl exec $etcdcontainer sh -c \"ETCDCTL_ENDPOINTS='https://127.0.0.1:2379' ETCDCTL_CACERT='/var/lib/rancher/rke2/server/tls/etcd/server-ca.crt' ETCDCTL_CERT='/var/lib/rancher/rke2/server/tls/etcd/server-client.crt' ETCDCTL_KEY='/var/lib/rancher/rke2/server/tls/etcd/server-client.key' ETCDCTL_API=3 etcdctl endpoint health --cluster --write-out=table\"\n"})}),"\n",(0,s.jsx)(r.p,{children:"etcdctl alarm list:"}),"\n",(0,s.jsx)(r.pre,{children:(0,s.jsx)(r.code,{className:"language-bash",children:"export CRI_CONFIG_FILE=/var/lib/rancher/rke2/agent/etc/crictl.yaml\netcdcontainer=$(/var/lib/rancher/rke2/bin/crictl ps --label io.kubernetes.container.name=etcd --quiet)\n/var/lib/rancher/rke2/bin/crictl exec $etcdcontainer sh -c \"ETCDCTL_ENDPOINTS='https://127.0.0.1:2379' ETCDCTL_CACERT='/var/lib/rancher/rke2/server/tls/etcd/server-ca.crt' ETCDCTL_CERT='/var/lib/rancher/rke2/server/tls/etcd/server-client.crt' ETCDCTL_KEY='/var/lib/rancher/rke2/server/tls/etcd/server-client.key' ETCDCTL_API=3 etcdctl alarm list\"\n"})}),"\n",(0,s.jsx)(r.p,{children:"curl metrics:"}),"\n",(0,s.jsx)(r.pre,{children:(0,s.jsx)(r.code,{className:"language-bash",children:"curl -L --cacert /var/lib/rancher/rke2/server/tls/etcd/server-ca.crt --cert /var/lib/rancher/rke2/server/tls/etcd/server-client.crt --key /var/lib/rancher/rke2/server/tls/etcd/server-client.key https://127.0.0.1:2379/metrics\n"})}),"\n",(0,s.jsx)(r.h2,{id:"kubernetes-events",children:"Kubernetes Events"}),"\n",(0,s.jsx)(r.p,{children:"Get All Events:"}),"\n",(0,s.jsx)(r.pre,{children:(0,s.jsx)(r.code,{className:"language-bash",children:"kubectl get events -A\n"})}),"\n",(0,s.jsx)(r.p,{children:"Get Events in Namespace:"}),"\n",(0,s.jsx)(r.pre,{children:(0,s.jsx)(r.code,{className:"language-bash",children:"kubectl get events -n mongodb\n"})}),"\n",(0,s.jsx)(r.h2,{id:"mount-points",children:"Mount Points"}),"\n",(0,s.jsx)(r.pre,{children:(0,s.jsx)(r.code,{className:"language-bash",children:"lsblk -a\nlsblk -l\nmount -afv\n"})}),"\n",(0,s.jsx)(r.h2,{id:"kubelet-configuration",children:"Kubelet Configuration"}),"\n",(0,s.jsxs)(r.ol,{children:["\n",(0,s.jsx)(r.li,{children:"To get the name of your worker nodes, run the following command:"}),"\n"]}),"\n",(0,s.jsx)(r.pre,{children:(0,s.jsx)(r.code,{className:"language-bash",children:"kubectl get nodes\n"})}),"\n",(0,s.jsxs)(r.ol,{start:"2",children:["\n",(0,s.jsx)(r.li,{children:"To open a connection to the API server, run the following command:"}),"\n"]}),"\n",(0,s.jsx)(r.pre,{children:(0,s.jsx)(r.code,{className:"language-bash",children:"kubectl proxy\n"})}),"\n",(0,s.jsx)(r.p,{children:"3.To check the node configz, open a new terminal, and then run the following command:"}),"\n",(0,s.jsx)(r.pre,{children:(0,s.jsx)(r.code,{className:"language-bash",children:'curl -sSL "http://localhost:8001/api/v1/nodes/node_name/proxy/configz" | python3 -m json.tool\n'})}),"\n",(0,s.jsx)(r.h2,{id:"service",children:"Service"}),"\n",(0,s.jsx)(r.p,{children:"Patch a Service as NodePort"}),"\n",(0,s.jsx)(r.pre,{children:(0,s.jsx)(r.code,{className:"language-bash",children:'kubectl patch svc your-svc -p \'{"spec": {"type": "NodePort"}}\'\n'})}),"\n",(0,s.jsx)(r.h2,{id:"argocd",children:"ArgoCD"}),"\n",(0,s.jsx)(r.p,{children:"Fetch ArgoCD Password"}),"\n",(0,s.jsx)(r.pre,{children:(0,s.jsx)(r.code,{className:"language-bash",children:"export KUBECONFIG=/etc/rancher/rke2/rke2.yaml PATH=$PATH:/var/lib/rancher/rke2/bin\nargocd_password=$(kubectl -n argocd get secret argocd-admin-password -o jsonpath='{.data.password}' | base64 --decode)\necho \"ArgoCD Password: $argocd_password\"\n"})}),"\n",(0,s.jsx)(r.h2,{id:"rabbitmq",children:"RabbitMQ"}),"\n",(0,s.jsx)(r.p,{children:"Accessing RabbitMQ Console"}),"\n",(0,s.jsx)(r.pre,{children:(0,s.jsx)(r.code,{className:"language-bash",children:"kubectl -n rabbitmq port-forward service/rabbitmq 8800:15672 --address 0.0.0.0\n# Login via the public IP of the machine where port forwarding command has been run\n# Make sure the IP of local machine is whitelisted\n\nrabbit_user=$(kubectl -n rabbitmq get secret rabbitmq-default-user -o jsonpath='{.data.username}' | base64 --decode)\nrabbit_password=$(kubectl -n rabbitmq get secret rabbitmq-default-user -o jsonpath='{.data.password}' | base64 --decode)\necho $rabbit_user\necho $rabbit_password\n"})}),"\n",(0,s.jsx)(r.h2,{id:"priorityclass",children:"PriorityClass"}),"\n",(0,s.jsx)(r.p,{children:"Check Priority Associated with each deployment"}),"\n",(0,s.jsx)(r.pre,{children:(0,s.jsx)(r.code,{className:"language-bash",children:"for deploy in $(kubectl get deploy -oname -n uipath | xargs); do echo $deploy;echo $(kubectl get $deploy -n uipath -o json | jq -r '.spec.template.spec.priorityClassName');  done\n"})}),"\n",(0,s.jsx)(r.h2,{id:"images",children:"Images"}),"\n",(0,s.jsx)(r.p,{children:"Fetch Images that correspond to deployments in all namespaces"}),"\n",(0,s.jsx)(r.pre,{children:(0,s.jsx)(r.code,{className:"language-bash",children:'for namespace in $(kubectl get ns | cut -d " " -f 1 | xargs); do echo $(kubectl get pods -n $namespace -o jsonpath="{.items[*].spec.containers[*].image}") $(kubectl get pods -n $namespace -o jsonpath="{.items[*].spec.initContainers[*].image}") | tr -s \'[[:space:]]\' \'\\n\' | sort | uniq; done\n'})}),"\n",(0,s.jsx)(r.h2,{id:"pods",children:"Pods"}),"\n",(0,s.jsx)(r.p,{children:"Pods that are unable to Schedule"}),"\n",(0,s.jsx)(r.pre,{children:(0,s.jsx)(r.code,{className:"language-bash",children:"kubectl get events -A | grep FailedScheduling\n"})}),"\n",(0,s.jsx)(r.p,{children:"Delete All Pod\u2019s in Namespace"}),"\n",(0,s.jsx)(r.pre,{children:(0,s.jsx)(r.code,{className:"language-bash",children:"kubectl delete --all pods --namespace=foo\n"})}),"\n",(0,s.jsx)(r.p,{children:"Delete all terminating pods"}),"\n",(0,s.jsx)(r.pre,{children:(0,s.jsx)(r.code,{className:"language-bash",children:"namespace=\"rook-ceph\"\nfor p in $(kubectl -n $namespace get pods | grep Terminating | awk '{print $1}'); do kubectl -n $namespace delete pod $p --grace-period=0 --force;done\n"})})]})}function h(e={}){const{wrapper:r}={...(0,a.a)(),...e.components};return r?(0,s.jsx)(r,{...e,children:(0,s.jsx)(d,{...e})}):d(e)}},1151:(e,r,n)=>{n.d(r,{Z:()=>l,a:()=>t});var s=n(7294);const a={},c=s.createContext(a);function t(e){const r=s.useContext(c);return s.useMemo((function(){return"function"==typeof e?e(r):{...r,...e}}),[r,e])}function l(e){let r;return r=e.disableParentContext?"function"==typeof e.components?e.components(a):e.components||a:t(e.components),s.createElement(c.Provider,{value:r},e.children)}}}]);