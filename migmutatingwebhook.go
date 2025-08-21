package main

import (
	"crypto/rsa"
	"crypto/tls"
	"crypto/x509"
	"encoding/pem"
	"fmt"
	"log"
	"migmutatingwebhook/pkg/certhandler"
	"migmutatingwebhook/pkg/secretmanager"
	webhookserver "migmutatingwebhook/pkg/server"
	"net/http"
)

var (
	serverTLSCert    *tls.Config
	clientTLSCert    *tls.Config
	caPEM            []byte
	rawLeafCert      []byte
	bytePrivateKey   []byte
	stringLeafCert   string
	stringCACert     string
	stringPrivateKey string
	err              error
)

func main() {

	log.Print("Initializing certificates")

	certSecretExists := secretmanager.GetSecret()

	if certSecretExists == true {

		fmt.Print("Secret was found. Starting server using existing tls configuration")

		migmutatingwebhookTLSSecret := secretmanager.GetCertSecretData()

		for key, value := range migmutatingwebhookTLSSecret.Data {

			if key == "ca.crt" {

				caPEM = value
			} else if key == "tls.crt" {

				rawLeafCert = value
			} else if key == "tls.key" {

				bytePrivateKey = value
			}

		}

		stringLeafCert = string(pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: rawLeafCert}))
		stringPrivateKey = string(pem.EncodeToMemory(&pem.Block{Type: "RSA PRIVATE KEY", Bytes: bytePrivateKey}))

		pemServerCert, err := tls.X509KeyPair(rawLeafCert, bytePrivateKey)

		if err != nil {

			log.Fatalln("Unable to create tls configuration from certificate secret ", err)
		}

		serverTLSCert = &tls.Config{Certificates: []tls.Certificate{pemServerCert}}

		certpool := x509.NewCertPool()
		certpool.AppendCertsFromPEM(caPEM)
		clientTLSCert = &tls.Config{RootCAs: certpool}

	} else {

		//generate certificates as they don't exist

		serverTLSCert, clientTLSCert, caPEM, err = certhandler.Certsetup()

		if err != nil {

			log.Fatalln("Certificate initialization failed ", err)

		}

		// read generated certificates to be used for secret generation

		rawLeafCert = serverTLSCert.Certificates[0].Certificate[0]
		rawPrivateKey := serverTLSCert.Certificates[0].PrivateKey.(*rsa.PrivateKey)

		//convert certificates to string

		stringLeafCert = string(pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: rawLeafCert}))
		stringCACert = string(pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: caPEM}))
		stringPrivateKey = string(pem.EncodeToMemory(&pem.Block{Type: "RSA PRIVATE KEY", Bytes: x509.MarshalPKCS1PrivateKey(rawPrivateKey)}))

		//create secret with newly generated certificates

		secretmanager.CreateCertSecret(stringLeafCert, stringPrivateKey, stringCACert)

	}

	//initialize server with TLS configuration

	webhookserver := webhookserver.Server{

		ServerTLSConf: serverTLSCert,
		ClientTLSConf: clientTLSCert,
		CaPEM:         caPEM,
	}

	log.Print("Starting webhook server. Listening on port 9443")

	handler := http.NewServeMux()
	handler.HandleFunc("/webhook", webhookserver.PostWebhook)

	https := &http.Server{

		Addr:      ":9443",
		TLSConfig: webhookserver.ServerTLSConf,
		Handler:   handler,
	}

	log.Fatalln(https.ListenAndServeTLS("", ""))

}
