---
title: Setup Azure Kubernetes Service with Terraform
date: 2020-10-07 08:40:46
author: Patrick Kerwood
excerpt: In this tutorial we will create an AKS cluster including an Azure Container Registry and a public IP resource for the Ingress Controller with Terraform. There will also be a quick how-to on installing the NGINX Ingress Controller using the Public IP created.
type: post
blog: true
tags: [terraform, azure, kubernetes]
---

{{ $frontmatter.excerpt }}

---

[[toc]]
## Prerequisites

First things first, install the tools needed for the job.

- [Terraform CLI](https://learn.hashicorp.com/tutorials/terraform/install-cli)
- [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli)
- [Helm 3](https://helm.sh/docs/intro/install/)

In this example I want my Terraform Service Principal to only have access to the AKS resource group instead of the whole Subscription. Same goes for my Virtual Network and Subnet. To limit the roles on the Service Principal, it will get the `Owner` role on the resource group and `Network Contributor` on the AKS node subnet.

The Resource Group, Virtual Network and Subnet must therefore be created/delivered prior to this tutorial.

## Get resource group ID

Login to Azure with the CLI tool and choose your working Subscription.

Get the resource group ID and store it in the `RG_ID` variable.

```sh
RG_ID=$(az group show -n <resourceGroupName> --query id -o tsv) && echo $RG_ID
```

## Create the Terraform Service Principal

Create a Service Principal with the Owner role on the resource group for Terraform to use. The SP has to get the `Owner` role to be able to create role assignments on the resource group.

You need the `Application Developer`, or higher, role for creating the Service Principal.

```sh
az ad sp create-for-rbac --name <servicePrincipalName> --role Owner --scopes=$RG_ID --years 99 -o json
```

You will get something simular to below.

Take a note of the `appId` and `password`. You will not be able to get the password again.

```json
{
  "appId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx", # Terraform client_id
  "displayName": "servicePrincipalName",
  "name": "http://servicePrincipalName",
  "password": "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx", # Terraform client_secret
  "tenant": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
}
```

Give the SP the `Network Contributor` role on the subnet you want to use. This is for AKS to be able to join the cluster nodes to the subnet. You will need the `Owner` role on the Virtual Net to create this assignment.

Get some ID's for the role assignment command. You can get the VNet values with `az network vnet list`.

```sh
# Service Principal ID
SP_ID=$(az ad sp list --display-name <servicePrincipalName> --query "[0].objectId" -o tsv) && echo $SP_ID

# Subnet ID
SUBNET_ID=$(az network vnet subnet show -n <subnetName> --vnet-name <vnetName> -g <vnetResourceGroup> --query id -o tsv) && echo $SUBNET_ID
```

Create the role assignment.

```sh
az role assignment create --role="Network Contributor" --assignee $SP_ID --scope $SUBNET_ID
```

Verify the role assignment.

```sh
az role assignment list --assignee $SP_ID --all
```

> Remember, these role assignments can take up to 20 min before going live, even though they are listed in above command.

## Configuring and running Terraform

Below is my Terraform `main.tf` file. I have added comments 
to descibe the sections.

All the variables in the variables section below, are defined in the `terraform.tfvars` file. If that file is present, Terraform will use the values from there. So basically there's no need to edit below file. All editing is done in `terraform.tfvars`.

### File: main.tf

```
##########################################################
#                      Variables                         #
##########################################################
# This section defines the variables needed.             #

variable "azure_subscription_id" {
  type = string
}
variable "azure_app_id" {
  type = string
}
variable "azure_client_secret" {
  type = string
}
variable "azure_tenant_id" {
  type = string
}


variable "vnet_group_name" {
  type = string
}
variable "vnet_name" {
  type = string
}
variable "subnet_name" {
  type = string
}


variable "aks_resource_group" {
  type = string
}
variable "aks_name" {
  type = string
}
variable "aks_vm_size" {
  type = string
}
variable "aks_node_count" {
  type = number
}


variable "acr_name" {
  type = string
}


##########################################################
#                       Provider                         #
##########################################################
# This section defines the Terraform Provider.           #
# https://www.terraform.io/docs/providers/index.html     #

provider "azurerm" {
  # Whilst version is optional, we /strongly recommend/ using it to pin the version of the Provider being used
  version = "=2.15.0"
  skip_provider_registration = true

  subscription_id = var.azure_subscription_id
  client_id       = var.azure_app_id
  client_secret   = var.azure_client_secret
  tenant_id       = var.azure_tenant_id

  features {}
}

##########################################################
#                 Main Resource Group                    #
##########################################################
# Since the resource group is already present, we just   #
# need to get the data from it.                          #

data "azurerm_resource_group" "main_rg" {
  name = var.aks_resource_group
}

##########################################################
#                Virtual Network Subnet                  #
##########################################################
# Getting data on the already existing subnet.

data "azurerm_subnet" "main_subnet" {
  name                 = var.subnet_name
  virtual_network_name = var.vnet_name
  resource_group_name  = var.vnet_group_name
}

##########################################################
#               Azure Kubernetes Service                 #
##########################################################
# Creates the Kubernetes cluster.                        #

resource "azurerm_kubernetes_cluster" "main_aks" {
  name                = var.aks_name
  location            = data.azurerm_resource_group.main_rg.location
  resource_group_name = data.azurerm_resource_group.main_rg.name
  dns_prefix          = var.aks_name

  default_node_pool {
    name           = "default"
    node_count     = var.aks_node_count
    vm_size        = var.aks_vm_size
    vnet_subnet_id = data.azurerm_subnet.main_subnet.id
  }

  identity {
    type = "SystemAssigned"
  }
}


##########################################################
#               Azure Container Registry                 #
##########################################################
# A Kubernetes cluster is not complete without a         #
# container registry.                                    #

resource "azurerm_container_registry" "acr" {
  name                     = var.acr_name
  resource_group_name      = data.azurerm_resource_group.main_rg.name
  location                 = data.azurerm_resource_group.main_rg.location
  sku                      = "Standard"
}


##########################################################
#         K8s Service Principle role assignment          #
##########################################################
# Below role assignments gives the "Network Contributor" #
# role to the AKS Service Principle to eg. read public   #
# IP resources and a role for the AKS cluster to be able #
# to pull images from the ACR.                           #

resource "azurerm_role_assignment" "role1" {
  scope                = data.azurerm_resource_group.main_rg.id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_kubernetes_cluster.main_aks.identity[0].principal_id
}


resource "azurerm_role_assignment" "role2" {
  scope                = azurerm_container_registry.acr.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.main_aks.kubelet_identity[0].object_id
}

#########################################################
#            Public IP for Ingress Controller           #
#########################################################
# In my setup, i chose to create a a Public IP resource #
# which will be used for my ingress controller.         #

resource "azurerm_public_ip" "ingress" {
  name                = "AKS-Ingress-Controller"
  resource_group_name = data.azurerm_resource_group.main_rg.name
  location            = data.azurerm_resource_group.main_rg.location
  allocation_method   = "Static"
}


#########################################################
#                        Output                         #
#########################################################
# Output the public IP address.                         #

output "ingress-ip" {
  value = azurerm_public_ip.ingress.ip_address
}

output "service-principal-id" {
  value = azurerm_kubernetes_cluster.main_aks.identity[0].principal_id
}

output "main-resource-group" {
  value = data.azurerm_resource_group.main_rg.name 
}
```

### File: terraform.tfvars

```
#########################################################
#                     Credentials                       #
#########################################################
azure_subscription_id = "xxxxxxxxxxxxx-xxxx-xxxx-xxxxxxxxxxxx" # Use: az account list
azure_app_id          = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" # Service Principal AppId.
azure_client_secret   = "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"   # Service Principal Password.
azure_tenant_id       = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" # Use: az account show

#########################################################
#                   Network Variables                   #
#########################################################
# These is values from the already existing Virtual Net #
# and subnet.

vnet_name               = "virtualNetworkName"           # Use: az network vnet list
vnet_group_name         = "virtualNetworkResourceGroup"  # Use: az network vnet list
subnet_name             = "subnetName"                   # Use: az network vnet subnet list --vnet-name <virtualNetworkName> -g <virtualNetworkResourceGroup> 

#########################################################
#               Azure Kubernetes Service                #
#########################################################

aks_resource_group = "resourceGroup"     # Name of your existing resource group.
aks_name           = "clusterName"
aks_vm_size        = "Standard_D2_v2"
aks_node_count     = 2

#########################################################
#                Azure Container Registry               #
#########################################################

acr_name = "acrname"  # Alphanumeric, no spaces, no hyphen, no caps.
```

Initiate the provider.

```sh
terraform init
```

Run below command to start deploying. After about 5-10 minutes your cluster should be up and running.

```sh
terraform apply
```

After Terraform is complete, go ahead and get the credentials for the cluster.

```sh
az aks get-credentials -n <clusterName> -g <clusterResourceGroup> -f kubeconfig
```

Connect to the cluster.

```sh
export KUBECONFIG=./kubeconfig
kubectl get all --all-namespaces
```

## One last role assignment

When the AKS cluster was created a Service Principal, with the same name as the cluster, was created. That Service Principal needs to be able to join the Load Balancer for the ingress to the subnet.

We will use Terraform to get the AKS Service Principal ID.

```sh
AKS_SP_ID=$(terraform output service-principal-id) && echo $AKS_SP_ID
```

Reuse the `$SUBNET_ID` variable and create the assignment.

```sh
az role assignment create --role="Network Contributor" --assignee $AKS_SP_ID --scope $SUBNET_ID
```

Verify the role assignment.

```sh
az role assignment list --assignee $AKS_SP_ID --all
```

## Installing NGINX Ingress

This example uses Helm 3 for installing NGINX Ingress.

Create the namespace for the Ingress Controller.

```sh
kubectl create namespace nginx-ingress
```

Add the `ingress-nginx` repo to Helm and update.

```sh
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
```

Before installing, we need the public IP we created and the resource group name. You can get those values from Terraform.

```sh
IP=$(terraform output ingress-ip) && echo $IP
RG=$(terraform output main-resource-group) && echo $RG
```

Run the Helm install command after creating above variables. To pickup the Public IP resource in the resource group, we the add the two last lines to the install command.

```sh{7,8}
helm install nginx-ingress ingress-nginx/ingress-nginx \
    --namespace nginx-ingress \
    --set controller.nodeSelector."beta\.kubernetes\.io/os"=linux \
    --set defaultBackend.nodeSelector."beta\.kubernetes\.io/os"=linux \
    --set controller.service.type=LoadBalancer \
    --set controller.service.externalTrafficPolicy=Local \
    --set controller.service.loadBalancerIP=$IP \
    --set controller.service.annotations."service\.beta\.kubernetes\.io/azure-load-balancer-resource-group"=$RG
```

Other parameters can be found here. [https://docs.nginx.com/nginx-ingress-controller/installation/installation-with-helm/](https://docs.nginx.com/nginx-ingress-controller/installation/installation-with-helm/)

Check that the LoadBalancer is ensured.

```sh
$ kubectl describe service nginx-ingress-ingress-nginx-controller --namespace nginx-ingress
...
Events:
  Type    Reason                Age   From                Message
  ----    ------                ----  ----                -------
  Normal  EnsuringLoadBalancer  69s   service-controller  Ensuring load balancer
  Normal  EnsuredLoadBalancer   7s    service-controller  Ensured load balancer
```

> If you get an error, the role assignment might not have fully binded in Azure. Grab a cop of coffee and wait for the retries, it takes some time, or run `helm uninstall nginx-ingress -n nginx-ingress` to uninstall the ingress controller and try to install it again.

And check that the ingress server got the public IP.

```sh
$ kubectl get service --namespace nginx-ingress
...
NAME                                               TYPE           CLUSTER-IP    EXTERNAL-IP      PORT(S)                      AGE
nginx-ingress-ingress-nginx-controller             LoadBalancer   10.0.84.146   51.144.58.94   80:31406/TCP,443:31019/TCP   6m28s
```

Ref: [https://docs.microsoft.com/en-us/azure/aks/ingress-basic](https://docs.microsoft.com/en-us/azure/aks/ingress-basic)

---