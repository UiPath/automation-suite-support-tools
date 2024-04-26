# Network Policy Tool
NetworkPolicyTool is a bash script that can be used to debug network policies or apply fixes.

It is mainly used to quickly allow all traffic for debugging.

## Installation
To install the tool from a linux machine (with internet access).
```
wget https://github.com/UiPath/automation-suite-support-tools/raw/main/Scripts/GeneralTools/networkPolicyDebugTool/networkPolicyTool.zip
unzip networkPolicyTool.zip
chmod -R 755 networkPolicyTool
```

For airgapped, download the zip file and transfer to the your linux machine. Then run the following commands:
```
unzip networkPolicyTool.zip
chmod -R 755 networkPolicyTool
```

## Usage
```
Usage: networkPolicyTool.sh [OPTIONS]
Options:
    -g | --allowAllTrafficGlobally | -g                  Used to manage a network policy that allows all traffic in all namespaces.
    -n | --allowAllTrafficInNamespace <namespace>        Used to manage a network policy that allows all traffic in a specific namespace.
    -c | --createNetworkPolicy <file>                    Used to create a network policy based on a pre-defined configuration file.
    -a | --add                                           Used to add a network policy.      
    -r | --remove                                        Used to remove a network policy.
    -h | --help                                          Display this help message.
```

## Examples
```
Examples:
    networkPolicyTool.sh --allowAllTrafficGlobally --add 
    networkPolicyTool.sh --allowAllTrafficGlobally --remove
    networkPolicyTool.sh --allowAllTrafficInNamespace mynamespace --add
    networkPolicyTool.sh --allowAllTrafficInNamespace mynamespace --remove
    networkPolicyTool.sh --createNetworkPolicy mynetworkpolicy.yaml --add
    networkPolicyTool.sh --createNetworkPolicy mynetworkpolicy.yaml --remove
    networkPolicyTool.sh --help
```

## Airflow fix (23.4.X - 23.10.2)
In some version of automation suite, the network policies for airflow would prevent DNS from working correctly.

To fix this run the following command:

```
sudo networkPolicyTool.sh --createNetworkPolicy ./Configs/networkPolicyTool/airflow.yaml --add
```