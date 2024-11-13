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

S3_BUCKET_NAME=solutions-engineering-demo-state-tf
S3_BUCKET_REGION=us-east-1


while getopts p:n:shcdvlr flag; do
    case "${flag}" in
    d) DRYRUN=echo ;;
    esac
done

if [ "${DRYRUN}" == "echo" ]; then
    echo -e "${RED}\nThis execution is a dry run. No changes will be made.${CLEAR}\n"
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

echo -e "You have selected: ${GREEN}$CLUSTER_WORKSPACE${CLEAR} cluster."

#echo -e "Run the following command in your shell to access the cluster:\n${GREEN}export KUBECONFIG=${CLUSTERS_PATH}/${CLUSTER_WORKSPACE}/kubeconfig${CLEAR}"

CLOUD_PROVIDER="${CLUSTER_WORKSPACE:0:3}"

echo -e "Cloud provider identified as: ${GREEN}${CLOUD_PROVIDER}${CLEAR}"

if [ "${CLOUD_PROVIDER}" == "eks" ]; then
    cd ${TERRAFORM_BASEDIR}/${TERRAFORM_EKS_DIR}
elif [ "${CLOUD_PROVIDER}" == "gke" ]; then
    cd ${TERRAFORM_BASEDIR}/${TERRAFORM_GKE_DIR}
else
    echo -e "${RED}The Cloud provider is not known or not supported. Exiting now.${CLEAR}"
    exit 0
fi

CLUSTER_PATH="${CLUSTERS_PATH}/${CLUSTER_WORKSPACE}"


echo "State is local"
terraform init -reconfigure -upgrade

${DRYRUN} terraform workspace select -or-create ${CLUSTER_WORKSPACE}

# Check the exit status of the previous command
if [ $? -ne 0 ]; then
    echo -e "${RED}Error:${CLEAR} 'terraform workspace select' command failed. Existing now."
    exit 1
fi

echo "State is local"
${DRYRUN} terraform plan -destroy -var-file=${CLUSTER_PATH}/terraform.tfvars -out=${CLUSTER_PATH}/tfplan
# Check the exit status of the previous command
if [ $? -ne 0 ]; then
    echo -e "${RED}Error:${CLEAR} 'terraform plan' command failed. Exiting now."
    exit 1
fi
${DRYRUN} terraform apply -auto-approve ${CLUSTER_PATH}/tfplan

if [ $? -ne 0 ]; then
    echo -e "${RED}Error:${CLEAR} 'terraform apply' command failed. Exiting now."
    exit 1
fi

${DRYRUN} terraform workspace select default

${DRYRUN} terraform workspace delete ${CLUSTER_WORKSPACE}

${DRYRUN} cd ${REALPATH}

if [ ! -d "${CLUSTERS_PATH}/archive/}" ] && [ -z "$DRYRUN" ]; then
    mkdir -p ${REALPATH}/clusters/archive/ 2>/dev/null
fi

${DRYRUN} mv ${CLUSTER_PATH} ${REALPATH}/clusters/archive/ 2>/dev/null # Supressing any warnings

#That's all folks!
exit 0