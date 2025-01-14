#!/bin/bash

set -e

# Set up parameters
resourceGroupName = "rcg"
deploymentName = "dn"

# Create a resource group name
az group create --name $resourceGroupName --location "eastus"

# Set up deployment of resources including AKS cluster, managed identity, etc
az deployment group create \
  --name $deploymentName \
  --resource-group $resourceGroupName \
  --template-file wi.bicep \

# Asslign values extracted from deployment to parameters below
clusterName=$(az deployment group show \
  -g $resourceGroupName  \
  -n $deploymentName \
  --query properties.outputs.clusterName.value \
  -o tsv)

userAssignedClientId=$(az deployment group show \
  -g $resourceGroupName  \
  -n $deploymentName \
  --query properties.outputs.userAssignedClientId.value \
  -o tsv)

serviceAccountNamespace=$(az deployment group show \
  -g $resourceGroupName  \
  -n $deploymentName \
  --query properties.outputs.serviceAccountNamespace.value \
  -o tsv)

serviceAccountName=$(az deployment group show \
  -g $resourceGroupName  \
  -n $deploymentName \
  --query properties.outputs.serviceAccountName.value \
  -o tsv)

keyVaultUri=$(az deployment group show \
  -g $resourceGroupName  \
  -n $deploymentName \
  --query properties.outputs.keyVaultUri.value \
  -o tsv)

secretName=$(az deployment group show \
  -g $resourceGroupName  \
  -n $deploymentName \
  --query properties.outputs.secretName.value \
  -o tsv)

# Get credentials to access AKS cluster
az aks get-credentials \
  --admin \
  --name $clusterName \
  --resource-group $resourceGroupName \

# Create configuration files for service account pod and workload pod. The images contains binary to get secrets wiht given name from a given keyvault. Image:https://github.com/Azure/azure-workload-identity/blob/main/examples/msal-go/main.go

cat <<EOF > workload-identity.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  annotations:
    azure.workload.identity/client-id: "${userAssignedClientId}"
  name: "${serviceAccountName}"
  namespace: "${serviceAccountNamespace}"
---
apiVersion: v1
kind: Pod
metadata:
  name: wi-demo
  namespace: ${serviceAccountNamespace}
  labels:
    azure.workload.identity/use: "true"
spec:
  serviceAccountName: ${serviceAccountName}
  containers:
    - image: ghcr.io/azure/azure-workload-identity/msal-go
      name: oidc
      env:
      - name: KEYVAULT_URL
        value: ${keyVaultUri}
      - name: SECRET_NAME
        value: ${secretName}
  nodeSelector:
    kubernetes.io/os: linux
EOF

# deploy the workload pod to run on the AKS 
kubectl apply -f workload-identity.yaml

# check pod's log if the secrets are successfully retrieved from keyvault
kubectl logs wi-demo -n ${serviceAccountNamespace}

  
