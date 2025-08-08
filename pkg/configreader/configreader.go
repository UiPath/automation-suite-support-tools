package configreader

import (
	"encoding/json"
	"log"
	"os"
)

type ModernDU struct {
	Enabled     bool        `json:"enabled"`
	Migsettings MigSettings `json:"mig-settgins"`
}

type MigSettings struct {
	Ocr       string `json:"ocr"`
	Extractor string `json:"extractor"`
	Training  string `json:"training"`
	Oob       string `json:"oob"`
	Resource  string `json:"resource"`
}

type ClassicDU struct {
	Resource string `json:"resource"`
}

type Configuratie struct {
	ModernDU  ModernDU  `json:"modern-du"`
	ClassicDU ClassicDU `json:"classic-du"`
}

func Readconfig() ( Configuratie) {

	configData, err := os.ReadFile("/config/config.json")

	if err != nil {

		log.Fatalln("Unable to read config file. Does the configmap exist? ", err)
	}

	var jsonconfig Configuratie

	jsonerr := json.Unmarshal(configData, &jsonconfig)

	if jsonerr != nil {

		log.Fatalln("Unable to unmarshal json configuration. ", jsonerr)
	}
	return jsonconfig
}
