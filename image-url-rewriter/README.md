## Disclaimer ##
This webhook is intended only as a temporary workaround until customers provision an external registry. We recommend setting up an external registry for long-term functionality and flexibility.

## How to build the docker image ##
```
docker build . -t image-url-rewriter:0.0.2 --platform linux/amd64
```

## Why is this workaround needed for OpenShift? ##

By default, the in-built registry in OpenShift organizes images by projects for storage and does not support nested paths in image URLs. For example, it supports the following formats:
```
image-registry.openshift-image-registry.svc:5000/uipath/dockerimage:0.0.1
image-registry.openshift-image-registry.svc:5000/vendor/dockerimage:0.0.1
```
However, it does not currently support formats such as:

```
image-registry.openshift-image-registry.svc:5000/vendor/uipath/dockerimage:0.0.1
image-registry.openshift-image-registry.svc:5000/dockerimage:0.0.1
```
This limitation requires customers to create projects in OpenShift with names matching the specific docker image paths.<br/> 
For example, you will need to create projects named uipath, vendor, etc., corresponding to the image path structure.

Additionally, some pods in certain scenarios may utilize images with a simpler format, such as `registry.openshift-image-registry.svc:5000/dockerimage:0.0.1` <br/>
In these cases, authentication errors may occur because OpenShift expects images to be pulled from specific project-organized paths.

To address this challenge temporarily, we have implemented a webhook as a workaround. <br/>
This webhook listens for the creation of pods within the uipath namespace and automatically rewrites the image URL from:

`registry.openshift-image-registry.svc:5000/dockerimage:0.0.1` <br/>
to <br/>
`registry.openshift-image-registry.svc:5000/uipath/dockerimage:0.0.1` <br/>
For this solution to work effectively, customers will need to push any relevant docker images to the uipath namespace. <br/>
Once this is done, the webhook can ensure smooth functionality without requiring further manual adjustments.

## Pre-requisites for using this webhook ##
<ul>
    <li>CertManager Operator</li>
    <li>Network policy to allow traffic from `openshift-host-network` namespace</li>
</ul>


## Network Policy definition ##

```
kind: NetworkPolicy
apiVersion: networking.k8s.io/v1
metadata:
  name: ingress-from-host-network
  namespace: os9936799
spec:
  podSelector: {}
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              policy-group.network.openshift.io/host-network: ''
  policyTypes:
    - Ingress
```