#!/bin/bash

# Set the green color variable
GREEN='\033[0;32m'
# Set the red color variable
RED='\033[0;31m'
# Clear the color after that
CLEAR='\033[0m'

echo -e "\n${GREEN}Waiting for all the nodes to appear in ready state${CLEAR}\n"

kubectl wait node --all --for condition=ready --timeout=600s

echo -e "\n"

# Check That all nodes are in ready state before redeploying test app
if [ $? -ne 0 ]; then
    echo -e "\n${RED}Warning:${CLEAR} Was waiting for the nodes to become ready for too long. Existing now."
fi