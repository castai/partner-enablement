#!/bin/bash

# Set the green color variable
GREEN='\033[0;32m'
# Set the red color variable
RED='\033[0;31m'
# Clear the color after that
CLEAR='\033[0m'

REALPATH=$(dirname $(realpath $0))
CLUSTERS_PATH="${REALPATH}/clusters"

TERRAFORM_BASEDIR=${REALPATH}/terraform
TERRAFORM_EKS_DIR=eks/eks_cluster_autoscaler_policies
TERRAFORM_GKE_DIR=gke/gke_cluster_autoscaler_policies

while getopts p:n:shcdvlr flag; do
    case "${flag}" in
    d) DRYRUN=echo ;;
    esac
done

if [ "${DRYRUN}" == "echo" ]; then
    echo -e "${RED}\nThis execution is a dry run. No changes will be made.${CLEAR}\n"
fi

# Checking if we have all the necessary environment variable set
if [ -z "${CASTAI_API_TOKEN}" ]; then
    read -p "Specify CAST AI API token: " CASTAI_API_TOKEN
fi

# Check if the directory exists
if [ ! -d "$CLUSTERS_PATH" ]; then
    echo "Directory not found: $CLUSTERS_PATH"
    exit 1
fi

# List all subdirectories (excluding $CLUSTERS_PATH itself and 'archive')
clusters=($(find "$CLUSTERS_PATH" -mindepth 1 -maxdepth 1 -type d -not -name 'archive' | xargs -n1 basename))

if [ ${#clusters[@]} -eq 0 ]; then
    echo -e "${RED}No clusters found in $CLUSTERS_PATH${CLEAR}. Exiting now."
    exit 0
fi

while true; do
    echo "Available clusters:"
    for ((i = 0; i < ${#clusters[@]}; i++)); do
        echo "[$((i + 1))] - ${clusters[i]}"
    done

    read -p "Enter the number of the cluster to use: " CLUSTER_CHOICE

    if [[ ! $CLUSTER_CHOICE =~ ^[0-9]+$ || $CLUSTER_CHOICE -lt 1 || $CLUSTER_CHOICE -gt ${#clusters[@]} ]]; then
        echo -e "${RED}Invalid choice. Please enter a valid number.${CLEAR}"
    else
        break # Exit the loop if a valid choice is made
    fi
done

CLUSTER_WORKSPACE="${clusters[$((CLUSTER_CHOICE - 1))]}"

echo -e "\nYou have selected: ${GREEN}$CLUSTER_WORKSPACE${CLEAR} cluster."

#echo -e "Run the following command in your shell to access the cluster:\n${GREEN}export KUBECONFIG=${CLUSTERS_PATH}/${CLUSTER_WORKSPACE}/kubeconfig${CLEAR}"

CLOUD_PROVIDER="${CLUSTER_WORKSPACE:0:3}"

echo -e "\nCloud provider identified as: ${GREEN}${CLOUD_PROVIDER}${CLEAR}\n"

if [ "${CLOUD_PROVIDER}" == "eks" ]; then
    cd ${TERRAFORM_BASEDIR}/${TERRAFORM_EKS_DIR}
elif [ "${CLOUD_PROVIDER}" == "gke" ]; then
    cd ${TERRAFORM_BASEDIR}/${TERRAFORM_GKE_DIR}
else
    echo -e "${RED}The Cloud provider is not known or not supported. Exiting now.${CLEAR}"
    exit 0
fi

CLUSTER_PATH="${CLUSTERS_PATH}/${CLUSTER_WORKSPACE}"

# Exporting kubeconfig for future use
export KUBECONFIG=${CLUSTER_PATH}/kubeconfig

#terraform init -upgrade

terraform workspace select -or-create ${CLUSTER_WORKSPACE}
# Check the exit status of the previous command
if [ $? -ne 0 ]; then
    echo -e "${RED}Error:${CLEAR} 'terraform workspace select' command failed. Existing now."
    exit 1
fi

CASTAI_CLUSTER_ID=$(terraform output -json castai_cluster_id | tr -d '"')


# Disarming Autoscaler

CASTAI_AUTOSCALER_DISARM_STATUS=$(curl -X 'PUT' -s -w '%{http_code}' -o /dev/null \
    "https://api.cast.ai/v1/kubernetes/clusters/${CASTAI_CLUSTER_ID}/policies" \
    -H "X-API-Key: ${CASTAI_API_TOKEN}" \
    -H 'accept: application/json' \
    -H 'Content-Type: application/json' \
    -d '{
        "enabled": false,
        "unschedulablePods": {
            "enabled": false
        },
        "nodeDownscaler": {
            "enabled": false,
            "emptyNodes": {
                "enabled": false
            },
            "evictor": {
                "aggressiveMode": true,
                "cycleInterval": "5s",
                "dryRun": false,
                "enabled": true,
                "nodeGracePeriodMinutes": 0,
                "scopedMode": false
            }
        },
        "clusterLimits": {
            "cpu": {
                "maxCores": 20,
                "minCores": 1
            },
            "enabled": false
        }
    }' && echo $response_code)

if [ ${CASTAI_AUTOSCALER_DISARM_STATUS} != "200" ]; then
    echo -e "\n${RED}Warning:${CLEAR} Disarming the autoscaler was not successfull. Response code: ${CASTAI_AUTOSCALER_DISARM_STATUS}. Existing now."
    exit 1
else
    echo -e "\n${GREEN}Autoscaler disarmed successfully.${CLEAR} Response code: ${CASTAI_AUTOSCALER_DISARM_STATUS}\n"
fi

terraform plan -var-file=${CLUSTER_PATH}/terraform.tfvars -out=${CLUSTER_PATH}/tfplan

# Check the exit status of the previous command
if [ $? -ne 0 ]; then
    echo -e "${RED}Error:${CLEAR} 'terraform plan' command failed. Exiting now."
    exit 1
fi

${DRYRUN} terraform apply -auto-approve ${CLUSTER_PATH}/tfplan

# Check the exit status of the previous command
if [ $? -ne 0 ]; then
    echo -e "${RED}Error:${CLEAR} 'terraform apply' command failed. Exiting now."
    exit 1
fi

echo -e "\n"

${DRYRUN} terraform workspace select default
${DRYRUN} cd ${REALPATH}

echo -e "\n${GREEN}Triggering reconciliation now.${CLEAR}"

RECONCILIATION_STATUS=$(curl -X 'POST' -s -w '%{http_code}' -o /dev/null \
    -H "X-API-Key: ${CASTAI_API_TOKEN}" \
    "https://api.cast.ai/v1/kubernetes/external-clusters/${CASTAI_CLUSTER_ID}/reconcile" \
    -H 'accept: application/json' \
    -d '' && echo $response_code)

if [ ${RECONCILIATION_STATUS} != "200" ]; then
    echo -e "\n${RED}Warning:${CLEAR} Reconciliation was not successfull. Response code: ${RECONCILIATION_STATUS}. Try reconcile manually from Console."
else
    echo -e "\n${GREEN}Reconciliation triggered successfully.${CLEAR} Response code: ${RECONCILIATION_STATUS}"
fi

#That's all folks!
exit 0
