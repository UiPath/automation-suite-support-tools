package webhook

import (
	"context"
	"encoding/json"
	"net/http"
	"strings"

	log "github.com/sirupsen/logrus"
	admv1 "k8s.io/api/admission/v1"
	corev1 "k8s.io/api/core/v1"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/webhook/admission"
)

type UrlRewriter struct {
	Name                    string
	Client                  client.Client
	Decoder                 admission.Decoder
	TargetRegistryNamespace string
	UiPathNamespace         string
	RegistryUrl             string
	IstioNamespace          string
}

func (m *UrlRewriter) Handle(ctx context.Context, req admission.Request) admission.Response {
	log.Infof("Handling admission request for %s/%s", req.Namespace, req.Name)

	if req.Operation != admv1.Create {
		log.Debugf("Skipping non-create operation: %s", req.Operation)
		return admission.Allowed("Only create operations are handled by this webhook")
	}

	pod := &corev1.Pod{}

	err := m.Decoder.Decode(req, pod)
	if err != nil {
		log.Errorf("Failed to decode pod from request: %v", err)
		return admission.Errored(http.StatusBadRequest, err)
	}

	if pod.ObjectMeta.Namespace != m.UiPathNamespace && pod.ObjectMeta.Namespace != m.IstioNamespace {
		log.Infof("Skipping pod %s/%s as it's not in the UiPath or Istio namespace (%s, %s)", pod.Namespace, pod.Name, m.UiPathNamespace, m.IstioNamespace)
		return admission.Allowed("Pod is not in the UiPath or Istio namespace, skipping")
	}

	log.Infof("Processing pod %s/%s with %d containers", pod.Namespace, pod.Name, len(pod.Spec.Containers))

	// Check each container's image
	for i := range pod.Spec.Containers {
		originalImage := pod.Spec.Containers[i].Image
		newImage := m.RewriteImageURL(originalImage)

		if originalImage != newImage {
			log.Infof("Rewriting image: %s -> %s", originalImage, newImage)
			pod.Spec.Containers[i].Image = newImage
		}
	}

	for i := range pod.Spec.InitContainers {
		originalImage := pod.Spec.InitContainers[i].Image
		newImage := m.RewriteImageURL(originalImage)

		if originalImage != newImage {
			log.Infof("Rewriting image: %s -> %s", originalImage, newImage)
			pod.Spec.InitContainers[i].Image = newImage
		}
	}

	marshaledPod, err := json.Marshal(pod)
	if err != nil {
		log.Errorf("Failed to marshall pod: %v", err)
		return admission.Errored(http.StatusInternalServerError, err)
	}

	log.Info("===========================================")

	return admission.PatchResponseFromRaw(req.Object.Raw, marshaledPod)

}

// RewriteImageURL - The core rewriting logic (exported for testing)
func (m *UrlRewriter) RewriteImageURL(image string) string {
	registryPrefix := m.RegistryUrl + "/"

	log.Debugf("Processing image: %s", image)

	// Only process internal registry images
	if !strings.HasPrefix(image, registryPrefix) {
		log.Debugf("Image %s doesn't have internal registry prefix, skipping", image)
		return image
	}

	// Remove the registry prefix to get the image path
	imagePath := strings.TrimPrefix(image, registryPrefix)

	// Split by '/' to check if it already has a namespace
	parts := strings.Split(imagePath, "/")

	// If it's a single-component name (no namespace), add configured namespace
	if len(parts) == 1 {
		newImage := registryPrefix + m.TargetRegistryNamespace + "/" + imagePath
		log.Debugf("Adding namespace to image: %s -> %s", image, newImage)
		return newImage
	}

	// If it already has proper namespace format, don't change it
	log.Debugf("Image %s already has namespace, keeping unchanged", image)
	return image
}
