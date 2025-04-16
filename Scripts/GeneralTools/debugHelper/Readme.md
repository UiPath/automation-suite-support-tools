# Debug Helper Tool

This tool provides a debug container with many tools pre-installed for troubleshooting in Kubernetes environments. Includes:

- AWS CLI
- Azure CLI
- kubectl
- helm
- jq
- yq
- curl
- wget
- python3 (with packages like boto3, azure-storage-blob, azure-identity etc.)
- git
- openssl
- Argocd CLI
- ...


# Docker Image Build, Push, and Deployment Guide

## **1. Prerequisites**
Before using this guide, ensure you have:
- Docker installed on your system.
- Access to a container registry
- Kubernetes cluster access (if deploying using Kubernetes).
- Proper authentication to push images to the registry.

---

## **2. Build and Push Docker Image**
The script `buildAndPushImage.sh` automates building, tagging and pushing the Docker image. It takes two arguments:
- Image tag (e.g., v1.0.0) [Required]
- Registry client (e.g., docker, podman) [Optional, defaults to docker]

```
./buildAndPushImage.sh <tag> [registry_client]
```

This will:

- Build the Docker image.
- Tag it as `sfbrdevhelmweacr.azurecre.io/sf-debug-helper:<tag>`.
- Push it to the container registry.

To push the image to Production ACR (`registry.uipath.com`) from Dev ACR, you need to use this [Image Promotion pipeline](https://dev.azure.com/uipath/Service%20Fabric/_build?definitionId=11728&_a=summary).

---

## **3. Offline Deployment**

If you need to transfer and push the image to another registry, try the following steps:

1. Pull the image from the registry
```
docker pull registry.uipath.com/sf-debug-helper:<tag>
```

2. Save the image to a tar file
```
docker save -o sf-debug-helper.tar registry.uipath.com/sf-debug-helper:<tag>
```

3. Copy the Tar File to Target System. Use scp or any other method:

```
scp sf-debug-helper.tar user@remote-server:/path/to/destination
```

4. Load the Image on the Target System

```
docker load -i sf-debug-helper.tar
```

5. Retag the Image for the New Registry

```
docker tag registry.uipath.com/sf-debug-helper:<tag> new-registry.com/your-image-name:<tag>
```

6. Push the Image to the New Registry

```
docker push new-registry.com/your-image-name:<tag>
```

**NOTE:**
You can use **podman** instead of **docker** for all the commands above.

---

## **4. Deploying the Image in Kubernetes**

Make necessary changes to the deployment.yaml file (such as the image tag) and apply it:
```
kubectl apply -f deployment.yaml
```
