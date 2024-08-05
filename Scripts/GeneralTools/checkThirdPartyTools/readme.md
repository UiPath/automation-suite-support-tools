# Check Third Party Tools
checkThirdPartyTools is a bash script that can be used to check for third party tools we have seen cause issues in the past.

IMPORTANT: If this tool returns a thirdparty tool, it does not mean the tool is incompatible. For example, certain
           illumio is a network security tool. In its default deployment it will break automation suite due to IP
           table manipulation. For customers who use this product, they contacted the vendor and the vendor provided
           instructions on how to configure the application to work with kubernetes and containers.

In general security tools should be transparent, meaning that the applications running on the machine are not aware of 
their presense and they do not interfere with application functionality. When our application fails due to one of these
tools, it typically means the tool is misconfigured or it has a bug that prevents legitimate applicaitons from executing.

If the vendor needs application specific information from UiPath, our support team is happy to provide it.


## Installation
To install the tool from a linux machine (with internet access).
```
wget https://github.com/UiPath/automation-suite-support-tools/raw/main/Scripts/GeneralTools/checkThirdPartyTools/checkThirdPartyTools.zip
unzip checkThirdPartyTools.zip
chmod -R 755 checkThirdPartyTools
```

For airgapped, download the zip file and transfer to the your linux machine. Then run the following commands:
```
unzip checkThirdPartyTools.zip
chmod -R 755 checkThirdPartyTools
```

## Usage
```
Usage: checkThirdPartyTools.sh [OPTIONS]
Description: This script will check the third party tools that could cause issues.
             The list is based on customer reports where we have found these
             services were causing issues.

             If a service is returned, it means that it might be causing an issue
             and should be investigated. It does not mean the service is incompatible
             with Automation Suite.

             We recomend disabling the tool to see if the issue is resolved. If it is,
             then the tool may be misconfigured or you may need to work with the vendor
             to resolve the issue.
Options:
  -h | --help : This will print the help message.
  -l | --list : This will list the services that could cause issues.
```

## Examples
```
Examples:
    checkThirdPartyTools.sh
    checkThirdPartyTools.sh -l
    checkThirdPartyTools.sh -h
```
