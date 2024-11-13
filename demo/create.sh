#!/bin/bash

# Set the green color variable
GREEN='\033[0;32m'
# Set the red color variable
RED='\033[0;31m'
# Clear the color after that
CLEAR='\033[0m'

REALPATH=$(dirname $(realpath $0))
TERRAFORM_BASEDIR=${REALPATH}/terraform
TERRAFORM_EKS_DIR=eks/eks_cluster_autoscaler_policies
TERRAFORM_GKE_DIR=gke/gke_cluster_autoscaler_policies
ARCHIVE_DIRECTORY=${REALPATH}/clusters/archive

# Setting reasonable defaults
DEFAULT_CLUSTER_NAME=demo
DEFAULT_CLOUD_PROVIDER="eks"
DEFAULT_MACHINE_COUNT=5
DEFAULT_INSTALL_CASTAI_AGENT=true
DEFAULT_INSTALL_DEMO_APP=true
DEFAULT_PAUSE_CRON_SCHEDULE="0 22 * * 1-5"
DEFAULT_RESUME_CRON_SCHEDULE="0 5 * * 1-5"
CLOUD_PROVIDERS=("eks" "gke")

AKS_REGION=eastus

S3_BUCKET_NAME=solutions-engineering-demo-state-tf
S3_BUCKET_REGION=us-east-1

# Helper functions

validate_provider() {
    local selected_provider="$1"
    for provider in "${CLOUD_PROVIDERS[@]}"; do
        if [ "$provider" == "$selected_provider" ]; then
            return 0
        fi
    done
    return 1
}

# Checking if there's a dry run option enabled
while getopts p:n:m:shcdfvlr flag; do
    case "${flag}" in
    d) DRYRUN=echo ;;
    p) CLOUD_PROVIDER=${OPTARG} ;;
    n) CLUSTER_NAME=${OPTARG} ;;
    m) MACHINE_COUNT=${OPTARG} ;;
    f)
        INSTALL_CASTAI_AGENT=true
        INSTALL_DEMO_APP=true
        ;;
    esac
done

# Checking if we have all the necessary environment variable set
if [ -z "${CASTAI_API_TOKEN}" ]; then
    read -p "Specify CAST AI API token: " CASTAI_API_TOKEN
fi

#Checking for necessary directories. If not exist, create everything we need to operate normally

if [ ! -d "$ARCHIVE_DIRECTORY" ]; then
    mkdir -p "$ARCHIVE_DIRECTORY"
    echo "Directory '$ARCHIVE_DIRECTORY' created."
else
    echo "Directory '$ARCHIVE_DIRECTORY' already exists. Skipping."
fi

# Prompt the user to select cloud provider if was not set with parameters
if [ -z "${CLOUD_PROVIDER}" ]; then
    while true; do
        echo "Select cloud provider (default: $DEFAULT_CLOUD_PROVIDER):"
        for ((i = 0; i < ${#CLOUD_PROVIDERS[@]}; i++)); do
            echo "[$((i + 1))] ${CLOUD_PROVIDERS[i]}"
        done
        read -p "Enter the number for the cloud provider: " PROVIDER_CHOICE

        if [ -z "$PROVIDER_CHOICE" ]; then
            CLOUD_PROVIDER="$DEFAULT_CLOUD_PROVIDER"
            break
        fi
        if validate_provider "${CLOUD_PROVIDERS[$PROVIDER_CHOICE - 1]}"; then
            CLOUD_PROVIDER="${CLOUD_PROVIDERS[PROVIDER_CHOICE - 1]}"
            break
        else
            echo "${RED}Invalid choice. Please select a valid provider from the list.${CLEAR}"
        fi
    done
else
    for provider in "${CLOUD_PROVIDERS[@]}"; do
        if [ "${provider}"=="${CLOUD_PROVIDER}" ]; then
            CLOUD_PROVIDER_FOUND=true
            break
        fi
        if [ $CLOUD_PROVIDER_FOUND==false ]; then
            echo -e "Unsupported Cloud provider: ${RED}${CLOUD_PROVIDER}${CLEAR}. Existing."
            exit 0
        fi
    done
fi

#Create EKS cluster template and collect missing data if any
if [ "${CLOUD_PROVIDER}" == "eks" ]; then
    if [ -z "$(aws configure get region)" ]; then
        echo -e "\n${RED}Warning:${CLEAR} Unable to get the default AWS region from the configuration. Using AWS_DEFAULT_REGION if set or us-east-1."
        EKS_REGION="${AWS_DEFAULT_REGION:=us-east-1}"
    else
        EKS_REGION=$(aws configure get region)
    fi
fi

#Create GKE cluster template and collect missing data if any
if [ "${CLOUD_PROVIDER}" == "gke" ]; then
    if [ -z $(gcloud config get-value project) ]; then
        echo -e "\n${RED}Warning:${CLEAR} Unable to get the default GCP project id."
        read -p "Specify GCP Project ID: " GCP_PROJECT_ID
    else
        GCP_PROJECT_ID=$(gcloud config get-value project)
    fi

    if [ -z $(gcloud config get-value compute/region) ]; then
        echo -e "\n${RED}Warning:${CLEAR} Unable to get the default GCP compute region. Using us-east1."
        GKE_REGION="us-east1"
    else
        GKE_REGION=$(gcloud config get-value compute/region)
    fi
fi

if [ -z "${MACHINE_COUNT}" ]; then
    read -p "Enter the number of machines (default: ${DEFAULT_MACHINE_COUNT}):" MACHINE_COUNT
    if [ -z ${MACHINE_COUNT} ]; then
        MACHINE_COUNT=${DEFAULT_MACHINE_COUNT}
    fi
fi

if [ -z "${CLUSTER_NAME}" ]; then
    read -p "Enter the cluster name (default: ${DEFAULT_CLUSTER_NAME}):" CLUSTER_NAME

    if [ -z ${CLUSTER_NAME} ]; then
        CLUSTER_NAME=${DEFAULT_CLUSTER_NAME}
    fi
fi

# Going to ask if the CAST AI needs to be installed if the variable was not set
if [ -z "${INSTALL_CASTAI_AGENT}" ]; then
    echo -e "Would you like to install CAST AI Agent (default: yes)?\n[1] yes \n[2] no"

    read -p "Enter the number for your choice: " INSTALL_CASTAI_AGENT_CHOICE
    case "$INSTALL_CASTAI_AGENT_CHOICE" in
    1) INSTALL_CASTAI_AGENT=true ;;
    2) INSTALL_CASTAI_AGENT=false ;;
    *) INSTALL_CASTAI_AGENT=${DEFAULT_INSTALL_CASTAI_AGENT} ;;
    esac
fi

# Going to ask if the Sockshop needs to be installed if the variable was not set
if [ -z "${INSTALL_DEMO_APP}" ]; then

    echo -e "Would you like to install Demo Application (default: yes)?\n[1] yes \n[2] no"

    read -p "Enter the number for your choice: " INSTALL_DEMO_APP_CHOICE
    case "$INSTALL_DEMO_APP_CHOICE" in
    1) INSTALL_DEMO_APP=true ;;
    2) INSTALL_DEMO_APP=false ;;
    *) INSTALL_DEMO_APP=${DEFAULT_INSTALL_DEMO_APP} ;;
    esac
fi

echo -e "\nCreating a cluster:\n\nName: ${GREEN}${CLUSTER_NAME}${CLEAR}\nProvider: ${GREEN}${CLOUD_PROVIDER}${CLEAR}\nWith CAST AI agent: $([[ $INSTALL_CASTAI_AGENT == true ]] && echo -e "${GREEN}yes${CLEAR}" || echo -e "${RED}no${CLEAR}")\nWith Demo Application: $([[ $INSTALL_DEMO_APP == true ]] && echo -e "${GREEN}yes${CLEAR}" || echo -e "${RED}no${CLEAR}")\n"

if [ "${DRYRUN}" == "echo" ]; then
    echo -e "${RED}\nThis execution is a dry run. No changes will be made.${CLEAR}\n"
fi

# Giving the cluster a unique name
CLUSTER_WORKSPACE="${CLOUD_PROVIDER}-${CLUSTER_NAME}-${USER:0:3}-$(date +'%m%d%H%M')"

# Defining the path where the Terraform will be storing relevan assets
CLUSTER_PATH="${REALPATH}/clusters/${CLUSTER_WORKSPACE}"

# Checking if we already have cluster directory. If so, getting out.
if [ -e ${CLUSTER_PATH} ] && [ -z "$DRYRUN" ]; then
    echo "Cluster ${CLUSTER_WORKSPACE} already exists. Stopping now."
    exit 1
fi

# Checking if not a dry run then creating cluster work directory
if [ -z $DRYRUN ]; then
    mkdir -p ${CLUSTER_PATH}
fi

if [ -z "$TZ" ]; then
    time_zone="$(date +%Z)"
    if [ "$time_zone" == "PDT" ] || [ "$time_zone" == "PST" ] ; then
        time_zone="PST8PDT"
    fi
else
    time_zone="$TZ"
fi

echo "Time zone is set to: $time_zone"


# Fetching the correct template for the cluster based on the cloud provider we're using
if [ "${CLOUD_PROVIDER}" == "eks" ] && [ -z "$DRYRUN" ]; then
    cat <<EOF >${CLUSTER_PATH}/terraform.tfvars
cluster_name = "${CLUSTER_WORKSPACE}" # don't change
cluster_region = "${EKS_REGION}" # don't change
castai_api_token = "${CASTAI_API_TOKEN}"
owner = "${USER}"
machines = "${MACHINE_COUNT}"
time_zone = "$time_zone"
pause_cron_schedule = "${DEFAULT_PAUSE_CRON_SCHEDULE}"
resume_cron_schedule = "${DEFAULT_RESUME_CRON_SCHEDULE}"
demo_app="${INSTALL_DEMO_APP}"
EOF

cd ${TERRAFORM_BASEDIR}/${TERRAFORM_EKS_DIR}
elif [ "${CLOUD_PROVIDER}" == "gke" ] && [ -z "$DRYRUN" ]; then
    GKE_ZONES=$(gcloud compute zones list --filter=${GKE_REGION}- --format=json | jq ".[].description" | paste -s -d, -)
    cat <<EOF >${CLUSTER_PATH}/terraform.tfvars
cluster_name = "${CLUSTER_WORKSPACE}" # don't change
cluster_region = "${GKE_REGION}" # don't change
cluster_zones = [${GKE_ZONES}] # don't change
castai_api_token = "${CASTAI_API_TOKEN}"
project_id = "${GCP_PROJECT_ID}"
owner = "${USER}"
machines = "${MACHINE_COUNT}"
time_zone = "$time_zone"
pause_cron_schedule = "${DEFAULT_PAUSE_CRON_SCHEDULE}"
resume_cron_schedule = "${DEFAULT_RESUME_CRON_SCHEDULE}"
demo_app="${INSTALL_DEMO_APP}"
EOF
    cd ${TERRAFORM_BASEDIR}/${TERRAFORM_GKE_DIR}
    gcloud auth application-default login #Required in order to run Terraform without specifying credentials
fi

# Enabling or disabling CAST AI agent based on the choice
if [ $INSTALL_CASTAI_AGENT == true ]; then
    mv castai.tf.off castai.tf 2>/dev/null # Supressing any warnings
else
    mv castai.tf castai.tf.off 2>/dev/null # Supressing any warnings
fi

# Running some terraform magic

#Defining the workspace before any init
export TF_WORKSPACE=${CLUSTER_WORKSPACE}

# Run the 'terraform init' command
${DRYRUN} terraform init -reconfigure -upgrade

echo -e "\n${GREEN}Current Workspace:${CLEAR} $(terraform workspace show)\n"

# Check the exit status of the previous command
if [ $? -ne 0 ]; then
    echo -e "${RED}Error:${CLEAR} 'terraform init' command failed. Existing now."
    exit 1
fi

# Run the 'terraform plan' command
${DRYRUN} terraform plan -var-file=${CLUSTER_PATH}/terraform.tfvars -out=${CLUSTER_PATH}/tfplan

# Check the exit status of the previous command
if [ $? -ne 0 ]; then
    echo -e "${RED}Error:${CLEAR} 'terraform plan' command failed. Exiting now."
    exit 1
fi

# Run the 'terraform apply' command
${DRYRUN} terraform apply -auto-approve ${CLUSTER_PATH}/tfplan

# Check the exit status of the previous command
if [ $? -ne 0 ]; then
    echo -e "${RED}Error:${CLEAR} 'terraform apply' command failed. Exiting now."
    exit 1
fi


${DRYRUN} export KUBECONFIG=${CLUSTER_PATH}/kubeconfig

echo -e "\n${GREEN}Kube config is set: ${CLEAR} ${KUBECONFIG}"

# Moving back where we started
cd ${REALPATH}

# Installing metrics server if not a dry run
echo -e "\nInstalling ${GREEN}Metrics Server${CLEAR}\n"
${DRYRUN} kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Check the exit status of the previous command
if [ $? -ne 0 ]; then
    echo -e "${RED}Error:${CLEAR} Unable to install metrics server. Try doing it manually by running: ${GREEN}kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml${CLEAR}"
    # Not existing, just reporting an error
fi

if [ -z "$DRYRUN" ]; then
    echo -e "\nRun the following command in your shell to access the cluster:\n${GREEN}export KUBECONFIG=${CLUSTER_PATH}/kubeconfig${CLEAR}"
fi

#That's all folks!
exit 0
