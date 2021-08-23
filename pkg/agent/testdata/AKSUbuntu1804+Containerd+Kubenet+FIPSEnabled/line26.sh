
retrycmd_if_failure() { r=$1; w=$2; t=$3; shift && shift && shift; for i in $(seq 1 $r); do timeout $t ${@}; [ $? -eq 0  ] && break || if [ $i -eq $r ]; then return 1; else sleep $w; fi; done }; ERR_OUTBOUND_CONN_FAIL=50; retrycmd_if_failure 100 1 10 nc -vz mcr.microsoft.com 443 >> /var/log/azure/cluster-provision-cse-output.log 2>&1 || time nc -vz mcr.microsoft.com 443 || exit $ERR_OUTBOUND_CONN_FAIL;
for i in $(seq 1 1200); do
grep -Fq "EOF" /opt/azure/containers/provision.sh && break;
if [ $i -eq 1200 ]; then exit 100; else sleep 1; fi;
done;

ADMINUSER=azureuser
MOBY_VERSION=
TENANT_ID=tenantID
KUBERNETES_VERSION=1.19.13
HYPERKUBE_URL=k8s.gcr.io/hyperkube-amd64:v1.19.13
KUBE_BINARY_URL=
KUBEPROXY_URL=
APISERVER_PUBLIC_KEY=
SUBSCRIPTION_ID=subID
RESOURCE_GROUP=resourceGroupName
LOCATION=southcentralus
VM_TYPE=vmss
SUBNET=subnet1
NETWORK_SECURITY_GROUP=aks-agentpool-36873793-nsg
VIRTUAL_NETWORK=aks-vnet-07752737
VIRTUAL_NETWORK_RESOURCE_GROUP=MC_rg
ROUTE_TABLE=aks-agentpool-36873793-routetable
PRIMARY_AVAILABILITY_SET=
PRIMARY_SCALE_SET=aks-agent2-36873793-vmss
SERVICE_PRINCIPAL_CLIENT_ID=ClientID
SERVICE_PRINCIPAL_CLIENT_SECRET='Secret'
KUBELET_PRIVATE_KEY=
NETWORK_PLUGIN=kubenet
NETWORK_POLICY=
VNET_CNI_PLUGINS_URL=https://acs-mirror.azureedge.net/azure-cni/v1.1.3/binaries/azure-vnet-cni-linux-amd64-v1.1.3.tgz
CNI_PLUGINS_URL=https://acs-mirror.azureedge.net/cni/cni-plugins-amd64-v0.7.6.tgz
CLOUDPROVIDER_BACKOFF=<nil>
CLOUDPROVIDER_BACKOFF_MODE=
CLOUDPROVIDER_BACKOFF_RETRIES=0
CLOUDPROVIDER_BACKOFF_EXPONENT=0
CLOUDPROVIDER_BACKOFF_DURATION=0
CLOUDPROVIDER_BACKOFF_JITTER=0
CLOUDPROVIDER_RATELIMIT=<nil>
CLOUDPROVIDER_RATELIMIT_QPS=0
CLOUDPROVIDER_RATELIMIT_QPS_WRITE=0
CLOUDPROVIDER_RATELIMIT_BUCKET=0
CLOUDPROVIDER_RATELIMIT_BUCKET_WRITE=0
LOAD_BALANCER_DISABLE_OUTBOUND_SNAT=<nil>
USE_MANAGED_IDENTITY_EXTENSION=false
USE_INSTANCE_METADATA=false
LOAD_BALANCER_SKU=
EXCLUDE_MASTER_FROM_STANDARD_LB=true
MAXIMUM_LOADBALANCER_RULE_COUNT=0
CONTAINER_RUNTIME=containerd
CLI_TOOL=ctr
CONTAINERD_DOWNLOAD_URL_BASE=https://storage.googleapis.com/cri-containerd-release/
NETWORK_MODE=
KUBE_BINARY_URL=
USER_ASSIGNED_IDENTITY_ID=userAssignedID
API_SERVER_NAME=
IS_VHD=true
GPU_NODE=false
SGX_NODE=false
MIG_NODE=false
CONFIG_GPU_DRIVER_IF_NEEDED=true
ENABLE_GPU_DEVICE_PLUGIN_IF_NEEDED=false
TELEPORTD_PLUGIN_DOWNLOAD_URL=
CONTAINERD_VERSION=
RUNC_VERSION=
CSE_STARTTIME=$(date)
/bin/bash /opt/azure/containers/provision.sh >> /var/log/azure/cluster-provision.log 2>&1
EXIT_CODE=$?
systemctl --no-pager -l status kubelet >> /var/log/azure/cluster-provision-cse-output.log 2>&1
OUTPUT=$(head -c 3000 "/var/log/azure/cluster-provision-cse-output.log")
KUBELET_START_TIME=$(echo "$OUTPUT" | cut -d ',' -f -1 | head -1)
KERNEL_STARTTIME=$(systemctl show -p KernelTimestamp | sed -e  "s/KernelTimestamp=//g" || true)
GUEST_AGENT_STARTTIME=$(systemctl show walinuxagent.service -p ExecMainStartTimestamp | sed -e "s/ExecMainStartTimestamp=//g" || true)
SYSTEMD_SUMMARY=$(systemd-analyze || true)
EXECUTION_DURATION=$(echo $(($(date +%s) - $(date -d "$CSE_STARTTIME" +%s))))

JSON_STRING=$( jq -n \
                  --arg ec "$EXIT_CODE" \
                  --arg op "$OUTPUT" \
                  --arg er "" \
                  --arg ed "$EXECUTION_DURATION" \
                  --arg ks "$KERNEL_STARTTIME" \
                  --arg cse "$CSE_STARTTIME" \
                  --arg ga "$GUEST_AGENT_STARTTIME" \
                  --arg ss "$SYSTEMD_SUMMARY" \
                  --arg kubelet "$KUBELET_START_TIME" \
                  '{ExitCode: $ec, Output: $op, Error: $er, ExecDuration: $ed, KernelStartTime: $ks, CSEStartTime: $cse, GuestAgentStartTime: $ga, SystemdSummary: $ss, BootDatapoints: { KernelStartTime: $ks, CSEStartTime: $cse, GuestAgentStartTime: $ga, KubeletStartTime: $kubelet }}' )
echo $JSON_STRING
exit $EXIT_CODE