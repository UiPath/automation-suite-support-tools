package server

import (
	"crypto/tls"
	"encoding/json"
	"fmt"
	"log"
	configreader "migmutatingwebhook/pkg/configreader"
	"migmutatingwebhook/pkg/configvalidator"
	"net/http"

	k8sadmissionReview "k8s.io/api/admission/v1"
	batchv1 "k8s.io/api/batch/v1"
)

type Server struct {
	ServerTLSConf *tls.Config
	ClientTLSConf *tls.Config
	CaPEM         []byte
}

func (s Server) PostWebhook(w http.ResponseWriter, r *http.Request) {

	var reviewRequest k8sadmissionReview.AdmissionReview
	var isPipeline bool

	isPipeline = false
	// read the configuration from configmap located in config/config.json

	migconfig := configreader.Readconfig()

	//validate read configuration

	validconfig := configvalidator.ClassicDU_ValidateConfig(migconfig.ClassicDU.Resource)

	if validconfig == false {

		log.Fatalln("Resource specified in configmap does not respect the format mig-xg.xxgb: ", migconfig.ClassicDU.Resource)
		return
	} else {

		// decode request body and load it into the revieRequest variable

		err := json.NewDecoder(r.Body).Decode(&reviewRequest)
		if err != nil {
			http.Error(w, fmt.Sprintf("JSON body in invalid format: %s\n", err.Error()), http.StatusBadRequest)
			return
		}

		//check if the request types are what we expect

		if reviewRequest.TypeMeta.Kind != "AdmissionReview" {
			http.Error(w, fmt.Sprintf("wrong APIVersion or kind: %s - %s", reviewRequest.TypeMeta.Kind), http.StatusBadRequest)
			log.Fatalln("wrong APIVersion or kind: ", reviewRequest.TypeMeta.Kind)
			return
		}

		// create patch type for response

		patchType := k8sadmissionReview.PatchTypeJSONPatch

		// create review response

		reviewResponse := &k8sadmissionReview.AdmissionResponse{
			UID:       reviewRequest.Request.UID,
			Allowed:   true,
			PatchType: &patchType,
		}

		fmt.Printf("debug: %+v\n", reviewRequest.Request)

		// check if the job is pipeline job

		job := &batchv1.Job{}

		if err := json.Unmarshal(reviewRequest.Request.Object.Raw, job); err != nil {

			log.Fatalln("Failed to read job yaml definition")
		}

		templateLabels := job.Spec.Template.Labels

:		for label, value := range templateLabels {

			if label == "app.uipath.com/component" && value == "pipeline" {

				isPipeline = true
			}

		}

		// check if we are trying to create a job, delete the existing GPU resource and the one loaded from config

		if reviewRequest.Request.RequestKind.Group == "batch" && reviewRequest.Request.RequestKind.Version == "v1" && reviewRequest.Request.RequestKind.Kind == "Job" && reviewRequest.Request.Operation == "CREATE" {
			if isPipeline == true {
				patch := `[{"op": "add", "path": "/spec/template/spec/containers/0/resources/requests/nvidia.com~1` + migconfig.ClassicDU.Resource + `", "value": "1"},{"op": "add", "path": "/spec/template/spec/containers/0/resources/limits/nvidia.com~1` + migconfig.ClassicDU.Resource + `", "value": "1"},{"op":"remove", "path": "/spec/template/spec/containers/0/resources/requests/nvidia.com~1gpu", "value": "1"},{"op": "remove", "path": "/spec/template/spec/containers/0/resources/limits/nvidia.com~1gpu", "value": "1"}]`
				reviewResponse.Patch = []byte(patch)
				fmt.Printf(patch)
			} else {
				patch := `[]`
				reviewResponse.Patch = []byte(patch)
				fmt.Printf(patch)
			}

		}

		// construct the final response

		response := k8sadmissionReview.AdmissionReview{

			TypeMeta: reviewRequest.TypeMeta,
			Response: reviewResponse,
		}

		out, err := json.Marshal(response)
		if err != nil {
			http.Error(w, fmt.Sprintf("JSON output marshal error: %s\n", err.Error()), http.StatusBadRequest)
			return
		}
		fmt.Printf("Got request, response: %s\n", string(out))
		fmt.Fprintln(w, string(out))

	}

}
