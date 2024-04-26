NetworkPolicyTool is a bash script that can be used to debug network policies or apply fixes.

It is mainly used to quickly allow all traffic for debuging.

Usage: networkPolicyTool.sh [OPTIONS]
Options:
    -g | --allowAllTrafficGlobally | -g                  Used to manage a network policy that allows all traffic in all namespaces.
    -n | --allowAllTrafficInNamespace <namespace>        Used to manage a network policy that allows all traffic in a specific namespace.
    -c | --createNetworkPolicy <file>                    Used to create a network policy based on a pre-defined configuration file.
    -a | --add                                           Used to add a network policy.      
    -r | --remove                                        Used to remove a network policy.
    -h | --help                                          Display this help message.
Examples:
    networkPolicyTool.sh --allowAllTrafficGlobally --add
    networkPolicyTool.sh --allowAllTrafficGlobally --remove
    networkPolicyTool.sh --allowAllTrafficInNamespace mynamespace --add
    networkPolicyTool.sh --allowAllTrafficInNamespace mynamespace --remove
    networkPolicyTool.sh --createNetworkPolicy mynetworkpolicy.yaml --add
    networkPolicyTool.sh --createNetworkPolicy mynetworkpolicy.yaml --remove
    networkPolicyTool.sh --help