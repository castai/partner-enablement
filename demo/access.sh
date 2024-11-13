#!/bin/bash

# Set the green color variable
GREEN='\033[0;32m'
# Set the red color variable
RED='\033[0;31m'
# Clear the color after that
CLEAR='\033[0m'

REALPATH=$(dirname $(realpath $0))
CLUSTERS_PATH="${REALPATH}/clusters"

# Check if the directory exists
if [ ! -d "$CLUSTERS_PATH" ]; then
    echo "Directory not found: $CLUSTERS_PATH"
    exit 1
fi

# List all subdirectories (excluding $CLUSTERS_PATH itself and 'archive')
clusters=($(find "$CLUSTERS_PATH" -mindepth 1 -maxdepth 1 -type d -not -name 'archive' | xargs -n1 basename))

if [ ${#clusters[@]} -eq 0 ]; then
    echo -e "${RED}No clusters found in $CLUSTERS_PATH${CLEAR}"
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
        break  # Exit the loop if a valid choice is made
    fi
done

CLUSTER_WORKSPACE="${clusters[$((CLUSTER_CHOICE - 1))]}"

echo -e "You have selected: ${GREEN}$CLUSTER_WORKSPACE${CLEAR} cluster."

echo -e "Run the following command in your shell to access the cluster:\n${GREEN}export KUBECONFIG=${CLUSTERS_PATH}/${CLUSTER_WORKSPACE}/kubeconfig${CLEAR}"