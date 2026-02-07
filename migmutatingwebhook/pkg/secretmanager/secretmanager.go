package secretmanager

import (
	"context"
	"errors"
	"log"
	"os"
	"path/filepath"

	coreV1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
	coreV1Types "k8s.io/client-go/kubernetes/typed/core/v1"
	"k8s.io/client-go/rest"
	"k8s.io/client-go/tools/clientcmd"
)

type k8sClientSet struct {
	k8sclientset *kubernetes.Clientset
}

var (
	found            bool
	k8sconfig        *rest.Config
	k8sSecretsClient coreV1Types.SecretInterface
	ctx              context.Context
)

func GetSecret() bool {

	k8sconfig, err := rest.InClusterConfig()

	if err != nil {

		log.Fatalln("Failed to get kubernetes config", err)

	}

	k8sclientset, err := kubernetes.NewForConfig(k8sconfig)

	if err != nil {

		log.Fatalln("Failed to build kubernetes client set", err)
	}

	currentNamespace, ok := os.LookupEnv("DEPLOYMENT_NAMESPACE")

	if ok == false {

		log.Fatalln("Failed to fatch current namespace from environment variable")
	}

	k8sSecretsClient = k8sclientset.CoreV1().Secrets(currentNamespace)

	ctx = context.Background()

	_, err = k8sSecretsClient.Get(ctx, "migmutatingwebhook-tls", metav1.GetOptions{})

	if err != nil {

		log.Print("Certificate secret not found. Creating certificates and secret ")

		found = false
	} else {

		found = true
	}

	return found

}

func CreateCertSecret(serverCert, serverKey, caCert string) {

	kuebConfigFilePath := filepath.Join("/etc", "rancher", "rke2", "rke2.yaml")

	if _, err := os.Stat(kuebConfigFilePath); errors.Is(err, os.ErrNotExist) {

		k8sconfig, err = rest.InClusterConfig()

		if err != nil {

			log.Fatalln("Failed to get kubernetes config", err)

		}

	} else {

		k8sconfig, err = clientcmd.BuildConfigFromFlags("", kuebConfigFilePath)

		if err != nil {

			log.Fatalln("Failed to get kubernetes config", err)
		}
	}

	k8sclientset, err := kubernetes.NewForConfig(k8sconfig)

	if err != nil {

		log.Fatalln("Failed to build kubernetes client set", err)
	}

	currentNamespace, ok := os.LookupEnv("DEPLOYMENT_NAMESPACE")

	if ok == false {

		log.Fatalln("Failed to fatch current namespace from environment variable")
	}

	k8sSecretsClient = k8sclientset.CoreV1().Secrets(currentNamespace)

	ctx = context.Background()

	certSecret := &coreV1.Secret{

		ObjectMeta: metav1.ObjectMeta{
			Name:      "migmutatingwebhook-tls",
			Namespace: currentNamespace,
		},

		Type: coreV1.SecretTypeTLS,
		StringData: map[string]string{
			"tls.crt": serverCert,
			"tls.key": serverKey,
			"ca.crt":  caCert,
		},
	}

	_, err = k8sSecretsClient.Create(ctx, certSecret, metav1.CreateOptions{})

	if err != nil {

		log.Fatalln("Failed to create certificate secret ", err)
	}

	log.Print("Certificate secret created")

}

func GetCertSecretData() *coreV1.Secret {

	kuebConfigFilePath := filepath.Join("/etc", "rancher", "rke2", "rke2.yaml")

	if _, err := os.Stat(kuebConfigFilePath); errors.Is(err, os.ErrNotExist) {

		k8sconfig, err = rest.InClusterConfig()

		if err != nil {

			log.Fatalln("Failed to get kubernetes config", err)

		}

	} else {

		k8sconfig, err = clientcmd.BuildConfigFromFlags("", kuebConfigFilePath)

		if err != nil {

			log.Fatalln("Failed to get kubernetes config", err)
		}
	}

	k8sclientset, err := kubernetes.NewForConfig(k8sconfig)

	if err != nil {

		log.Fatalln("Failed to build kubernetes client set", err)
	}

	currentNamespace, ok := os.LookupEnv("DEPLOYMENT_NAMESPACE")

	if ok == false {

		log.Fatalln("Failed to fatch current namespace from environment variable")
	}

	k8sSecretsClient = k8sclientset.CoreV1().Secrets(currentNamespace)

	ctx = context.Background()

	secret, err := k8sSecretsClient.Get(ctx, "migmutatingwebhook-tls", metav1.GetOptions{})

	if err != nil {

		log.Print("Unable to retrieve certificate secret")

	}

	return secret

}
