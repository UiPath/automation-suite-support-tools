package main

import (
	"log"
	"migmutatingwebhook/pkg/certhandler"
	webhookserver "migmutatingwebhook/pkg/server"
	"net/http"
)

func main() {

	log.Print("Initializing certificates")

	serverTLSCert, clientTLSCert, caPEM, err := certhandler.Certsetup()

	if err != nil {

		log.Fatalln("Certificate initialization failed ", err)

	}

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
