package configvalidator

import (
	"regexp"
)

func ClassicDU_ValidateConfig(configuratie string) bool {

	//validate if the configuration read from the configmap respects the format of mig-xg.xxgb

	validated, _ := regexp.MatchString("^mig-[0-9]g\\.[0-9][0-9]gb$", configuratie)

	return validated

}
