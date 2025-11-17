package main

import (
	"flag"
	"os"

	hook "github.com/uipath/service-fabric-utils/image-url-rewriter-webhook/webhook"
	_ "k8s.io/client-go/plugin/pkg/client/auth/gcp"
	"sigs.k8s.io/controller-runtime/pkg/client/config"
	logf "sigs.k8s.io/controller-runtime/pkg/log"
	"sigs.k8s.io/controller-runtime/pkg/log/zap"
	"sigs.k8s.io/controller-runtime/pkg/manager"
	"sigs.k8s.io/controller-runtime/pkg/manager/signals"
	"sigs.k8s.io/controller-runtime/pkg/webhook"
	"sigs.k8s.io/controller-runtime/pkg/webhook/admission"
)

var log = logf.Log.WithName("image-url-rewriter-controller")

type HookParameters struct {
	certDir                 string
	targetRegistryNamespace string
	uipathNamespace         string
	istioNamespace          string
	registryUrl             string
	port                    int
}

func main() {
	var params HookParameters

	flag.StringVar(&params.targetRegistryNamespace, "targetRegistryNamespace", "default", "The namespace the images are stored in")
	flag.StringVar(&params.certDir, "certDir", "/etc/webhook/config/certs/", "Webhook certificate folder")
	flag.StringVar(&params.uipathNamespace, "uipathNamespace", "default", "The namespace in which UiPath applications are deployed")
	flag.StringVar(&params.istioNamespace, "istioNamespace", "istio-system", "The namespace in which Istio is deployed")
	flag.StringVar(&params.registryUrl, "registryUrl", "", "The docker registry URL to use")
	flag.IntVar(&params.port, "port", 8443, "Webhook port")

	flag.Parse()

	logf.SetLogger(zap.New())

	entryLog := log.WithName("entrypoint")

	// Setup a Manager
	entryLog.Info("setting up manager")
	mgr, err := manager.New(config.GetConfigOrDie(), manager.Options{
		WebhookServer: &webhook.DefaultServer{
			Options: webhook.Options{
				Port:    params.port,
				CertDir: params.certDir,
			},
		},
	})
	if err != nil {
		entryLog.Error(err, "unable to set up overall controller manager")
		os.Exit(1)
	}

	// Setup webhooks
	entryLog.Info("setting up webhook server")
	hookServer := mgr.GetWebhookServer()

	// Create the admission decoder and assign it to the handler
	decoder := admission.NewDecoder(mgr.GetScheme())

	ci := &hook.UrlRewriter{
		Name:                    "webhook",
		Client:                  mgr.GetClient(),
		Decoder:                 decoder,
		TargetRegistryNamespace: params.targetRegistryNamespace,
		UiPathNamespace:         params.uipathNamespace,
		RegistryUrl:             params.registryUrl,
		IstioNamespace:          params.istioNamespace,
	}

	entryLog.Info("registering webhooks to the webhook server")
	hookServer.Register("/mutate", &webhook.Admission{Handler: ci})

	entryLog.Info("starting manager", "targetRegistryNamespace", params.targetRegistryNamespace, "uipathNamespace", params.uipathNamespace, "port", params.port, "certDir", params.certDir)
	if err := mgr.Start(signals.SetupSignalHandler()); err != nil {
		entryLog.Error(err, "unable to run manager")
		os.Exit(1)
	}

}
