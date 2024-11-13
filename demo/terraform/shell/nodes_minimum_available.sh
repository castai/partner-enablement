#!/bin/bash

# Set the green color variable
GREEN='\033[0;32m'
# Set the red color variable
RED='\033[0;31m'
# Clear the color after that
CLEAR='\033[0m'

desired_node_count=5         # Set your desired number of nodes
timeout_duration=$((5 * 60)) # 5 minutes in seconds

start_time=$(date +%s)


# Updating credentials so we can access the cluster
if [ "${CLOUD_PROVIDER}" == "aks" ]; then
    az aks get-credentials --name ${CLUSTER_NAME} --resource-group ${CLUSTER_NAME} -f $KUBECONFIG
elif [ "${CLOUD_PROVIDER}" == "eks" ]; then
    aws eks update-kubeconfig --region ${REGION} --name ${CLUSTER_NAME}
elif [ "${CLOUD_PROVIDER}" == "gke" ]; then
    echo -e "\nFetching GKE cluster credentials..."
    gcloud container clusters get-credentials ${CLUSTER_NAME} --region ${REGION}
    until [ $? -eq 0 ]; do
        echo "${RED}Retrying in 10 seconds...${CLEAR}"
        sleep 10
        gcloud container clusters get-credentials ${CLUSTER_NAME} --region ${REGION}
    done
fi

while true; do
    current_node_count=$(kubectl get nodes --no-headers | wc -l | tr -d '[:space:]')
    current_time=$(date +%s)
    elapsed_time=$((current_time - start_time))

    if [ "$current_node_count" -ge "$desired_node_count" ]; then
        echo -e "\n${GREEN}Minimum desired number of nodes ($desired_node_count) is reached.${CLEAR}\n"
        break
    elif [ "$elapsed_time" -ge "$timeout_duration" ]; then
        echo -e "\n${RED}Warning:${CLEAR} Was waiting for the nodes for too long. Existing now."
        exit 1
    else
        echo "Waiting for nodes to be provisioned. Current count: $current_node_count / Minimum desired count: $desired_node_count"
        sleep 5 # Adjust the sleep interval as needed
    fi
done
