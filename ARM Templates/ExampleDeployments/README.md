# Example Deployments  

Having all the nested templates doesn't help you unless your able to utilize them to build real world architectures. In this section we are going to focus on putting together nested templates into a real world architecture. Giving you plenty of examples and providing the expertise for you to build your own environments in simular deployments.  

## Table of Content  

* [AKS Applications](#AKSApplications)
     - [AppGW-AKS](#AppGWAKS)  

# <a name="AKSApplications"></a>AKS Applications  
Below we'll walk through some depoloyments that involve an AKS Application being deployed in Azure

## <a name="AppGWAKS"></a>Simple Web Application deployed in AKS and exposed thorugh Application Gateway  
This architecture is made of of the following resources:  
- Virtual Network with the following Subnets  
    - AppGW-SN  
    - AKS-SN  
    - Data-SN  
    - Bastion-SN  
    - Management-SN  
- Application Gateway v2 with WAF and Public IP  
- AKS Cluster
- Azure Container Registry with Private Endpoint  
- Azure Bastion  
- Virtual Machine  
- Azure Private DNS Zones for Private Endpoints  
- Log Analytics Workspace for Monitoring  
- Application Insights Instance for APIM and API  

<img src="./images/2-Tier-AppGW-AKS.png" alt="Environment"  Width="900">  

This is an example of a simple web application being deployed in AKS. The deployment does not expose AKS directly but requires external users to go throuh the Application Gateway to access the website. We will secure the traffic between the subnets using Network Security Groups with the added protection of the WAF being utilized by the Application Gateway. ACR will Private Endpoints and not allow access to their public endpoints.  

### Virtual Network Architecture  
Below we will outline the Virtual Networks and NSGs associated with them.  

#### Application Gateway Subnet  
We protect this subnet utilizing both a NSG and the WAF associated with the Application Gateway. The NSG will only allow traffic on port 443 for end user access and the ports needed for the Application Gateway health status. Below outlines the NSG that is created in the template.  

| Name          | Priority | Description   |  Direction     | Source/Destination Port     | Source/Destination Address  | Protocol  | 
|-------------------|-------------------|-------------------|-------------------|-------------------|-------------------|-------------------|
| Allow-443-GW          | 100 | Allow 443 Traffic Inbound from GW Subnet | Inbound  | \*\/443 | \<GW Subnet\>/\*   | TCP |
| Allow-443-Mgmt          | 110 | Allow 443 Traffic Inbound from Mgmt Subnet | Inbound  | \*\/443 | \<Mgmt Subnet\>/\*   | TCP |
| Allow-HealthProbe     | 110 | Allow the AppGW Health Status | Inbound  | \*\/65200-65535 | Azure/\* | TCP |
| Deny-All-Inbound		   | 500 | Deny All Traffic | Inbound | \*/\*   | \*/\* | TCP |  

#### AKS Subnet  
This subnet will have an empty NSG attached to it. We will utilize ingress and egress controllers within AKS to control traffic.  

#### Data Subnet  
The data subnet in this template only contains the virtual nics for the private endpoints. In the furture we may add aditon data points for the application so we will go ahead and restrict this and deny all traffic. If other data points are added we would allow that traffic at that point. Note that even through the virtual nic sits on this VNET the NSGs do not take affect for the traffic to it.   

| Name          | Priority | Description   |  Direction     | Source/Destination Port     | Source/Destination Address  | Protocol  | 
|-------------------|-------------------|-------------------|-------------------|-------------------|-------------------|-------------------|
| deny-all-ib		   | 500 | Deny all inbound traffic | Inbound | \*/\*   | \*/\* | TCP |  
| deny-all-ob		   | 500 | Deny all outbound traffic | Outbound | \*/\*   | \*/\* | TCP |  
  

#### Management Subnet  
The management subnet contains a virtual machine with only a private IP address. This is a management jump box that will be accessed externally through Azure Bastion. So we will allow the Azure Bastion subnet access.  

| Name          | Priority | Description   |  Direction     | Source/Destination Port     | Source/Destination Address  | Protocol  | 
|-------------------|-------------------|-------------------|-------------------|-------------------|-------------------|-------------------|
| Allow-Bastion		   | 100 | Allow Bastion subnet | Inbound | \*/\*   | \<Bastion Subnet\>/\* | TCP |  
| deny-all-ib		   | 500 | Deny all inbound traffic | Inbound | \*/\*   | \*/\* | TCP |  

#### Virtual Network Deployment  
In order to deploy the Virtual Network we need to utilize 4 nested templates  
1) VNet  
2) GetSubnetAddressPrefix  
3) NSG-Empty-ExistingSubnet  
4) NSG-ExistingSubnet  

For every NSG you deploy you'll need to utilize GetSubnetAddressPrefix and then either NSG-Empty-ExistingSubnet or NSG-ExistingSubnet. 

First we deploy the Virtual Network with the subnets defines. The following Parameters are used for the VNet deployment:  

      "addressRange": {
        "type": "String",
        "defaultValue":"192.168.1.0/24",
        "metadata": {
          "description": "Administrator password for the local admin account"
        }
      },
      "subnets": {
        "type": "array",
        "defaultValue": [
          "aks-SN|192.168.1.0/25|Enabled",
          "data-SN|192.168.1.176/28|Disabled",
          "shared-SN|192.168.1.160/28|Enabled",
          "AzureBastionSubnet|192.168.1.128/28|Enabled",
          "AppGW-SN|192.168.1.144/28|Enabled"
        ]
      }

The following variable is used to define the VNet name: 

      "vnetName": "[concat(parameters('deploymentPrefix'),'vnet',uniqueString(parameters('resourceGroup')))]"

The following is used to deploy the VNet:  

            "vNETName": {
              "value": "[variables('vnetName')]"
            },
            "addressRange": {
              "value": "[parameters('addressRange')]"
            },
            "subnets": {
              "value": "[parameters('subnets')]"
            }

Now that we have a virtual network and subnets we need to create and attach NSGs to them. Below I'll walk through the AKS NSG deployment. To get the AKS Address range we call "GetSubnetAddressPrefix" using the following:

            "vnetName": {
              "value": "[variables('vnetName')]"
            },
            "subnetName": {
              "value": "AKS-SN"
            }

Now that we have the address prefix for the AKS subnet we can call "NSG-Empty-ExistingSubnet" using the following:  

            "virtualNetworkName": {
              "value": "[variables('vnetName')]"
            },
            "subnetName": {
              "value": "AKS-SN"
            },
            "addressPrefix": {
              "value": "[reference('getAKSAddressPrefix').outputs.addressPrefix.value]"
            },
            "nsgName": {
              "value": "AKS-NSG"
            }

### Application Gateway Deployment  
Application Gateway WAF v2 is deployed for this architecture. We deploy with both a Public and Private endpoint for the gateway and inject it onto the Application Gateway Subnet. 

In order to deploye the Application Gateway we need to first create a Public IP Address. We call the Nested Template "PublicIPAddress" using the following values.  

            "publicIpAddressName": {
              "value": "[concat(variables('applicationGatewayName'),'pip1')]"
            },
            "sku": {
                "value": "Standard"
            },
            "allocationMethod": {
                "value": "Static"
            }  

The Application Gateway also utilizes a certificate that is stored in Key Vault. This is a pre-existing key vault that you should upload your certificate to ahead of time. We will create a User Assigned Managed Identity and grant that Managed Identity the Access Policy needed to retrieve the certificate.  

First we create the Managed Identity using the Nested Template "ManagedIdentity":

            "identityName": {
                "value": "[concat(variables('applicationGatewayName'),'-identity')]"
            }  

Then we grant it permissions to Key Vault using the Nested Template "KeyVaultAccessPolicy" (Note: You have to set the variable keyVaultName to the existing Key Vault where the certificates are placed)  

            "keyVaultName": {
                "value": "[variables('keyVaultName')]"
            },
            "secrets": {
                "value": [
                    "Get",
                    "List",
                    "Set",
                    "Delete",
                    "Recover",
                    "Backup",
                    "Restore"
                ]
            },
            "objectId": {
                "value": "[reference('createManagedIdentity').outputs.principalId.value]"
            }
          }

Now we are able to deploy the Application Gateway. Below are the Parameters in the 3-Tier-APIM-AKS-SQL.json related to the Application Gateway.  
      "deploymentPrefix": {
          "type": "string",
          "defaultValue": "poc"
      },
      "appgwtier": {
        "type": "string",
        "defaultValue": "WAF_v2"
      },
      "appgwskuSize": {
          "type": "string",
          "defaultValue": "WAF_v2"
      },
      "appgwzones": {
          "type": "array",
          "defaultValue": [
                  "1",
                  "2",
                  "3"
          ]
      },
      "appgwMinCapacity": {
          "type": "int",
          "defaultValue": 1
      },
      "appgwMaxCapacity": {
          "type": "int",
          "defaultValue": 3
      }  

We set the name of the application gateway utilizing the below variable in the template.  

      "applicationGatewayName": "[concat(parameters('deploymentPrefix'),'appgw',uniqueString(parameters('resourceGroup')))]"  

Now we are ready to execute the creation of the Application Gateway using the following:  

            "applicationGatewayName": {
                "value": "[variables('applicationGatewayName')]"
            },
            "tier": {
                "value": "[parameters('appgwtier')]"
            },
            "skuSize": {
                "value": "[parameters('appgwskuSize')]"
            },
            "minCapacity": {
                "value": "[parameters('appgwMinCapacity')]",
            },
            "maxCapacity": {
                "value": "[parameters('appgwMaxCapacity')]",
            },
            "zones": {
                "value": "[parameters('appgwzones')]"
            },
            "subnetID": {
                "value": "[concat(reference('deployVNET').outputs.vnetId.value,'/subnets/AppGW-SN')]"
            },
            "publicIpAddressesIds": {
                "value": [
                  "[concat('PIP1|',reference('deployPublicIP1').outputs.publicIPID.value )]"
                ]
            },
            "keyVaultName": {
              "value": "[variables('keyVaultName')]"
            },
            "identityID": {
                "value": "[reference('createManagedIdentity').outputs.resourceId.value]"
            },
            "certificates": {
                "value": "[parameters('certificates')]"
            },
            "frontendPorts": {
                "value": [
                  "HTTPS-443|443"
                ]
            },
            "backendAddresses": {
                "value": [
                  "[concat('APIMGW|', variables('apimName'),'.azure-api.net')]"
                ]
            },
            "backendHttpSettings": {
                "value": [
                  "APIM-HTTPSSetting|443|Https|Disabled|30|/"
                ]
            },
            "httpListeners": {
                "value": [
                  "APIMListener|PIP1|HTTPS-443"
                ]
            },
            "requestRoutingRules": {
                "value": [
                  "Apim-RoutingRule|APIMListener|APIMGW|APIM-HTTPSSetting"
                ]
            }  

This will configure the application gateway to listen on port 443 using the certificate configured in Key Vault. It has a single backend pool that sends traffic on port 443 to the APIM GW address that will be created later.  

The last step for the application Gateway is to configure the diagnostic and metrics to be sent to a log analytics workspace. Before we do this we need to create the workspace using the Nested Template "Log_Analytics_Workspace" using the following:  

              "value": "[variables('laName')]"  

Note that the laName variable is set like this: "[concat(parameters('deploymentPrefix'),'la',uniqueString(parameters('resourceGroup')))]"  

Now that we have a Log Analytics Workspace we can use the Nested Template "AppGWDiagnostics" using the following:  

            "workspaceId": {
                "value": "[reference('deployLogAnalytics').outputs.workspaceId.value]"
            },
            "logs": {
                "value": [
                  "ApplicationGatewayAccessLog",
                  "ApplicationGatewayPerformanceLog",
                  "ApplicationGatewayFirewallLog"
                ]
            },
            "metrics": {
                "value": [
                  "AllMetrics"
                ]
            },
            "appgwName": {
              "value": "[variables('applicationGatewayName')]"
            }  

### AKS Deployment  
Next we will deploy our middle tier which runs AKS. The AKS cluster will be deployed privatley using Private Endpoints.  

You can deploy AKS using the following parameters:  

            "AksresourceName": {
              "value": "[variables('AksresourceName')]"
            },
            "nodeResourceGroup":{
              "value": "[variables('nodeResourceGroup')]"
            },
            "VNetName" : {
              "value": "[variables('vNETName')]"
            },
            "SubnetName" : {
              "value": "AKS-SN"
            },  
            "dnsPrefix": {
                "value": "[variables('dnsPrefix')]"
            },
            "kubernetesVersion": {
                "value": "[parameters('kubernetesVersion')]"
            },
            "networkPlugin": {
                "value": "[parameters('networkPlugin')]"
            },
            "enableRBAC": {
                "value": "[parameters('enableRBAC')]"
            },
            "enablePrivateCluster": {
                "value": "[parameters('enablePrivateCluster')]"
            },
            "enableHttpApplicationRouting": {
                "value": "[parameters('enableHttpApplicationRouting')]"
            },
            "networkPolicy": {
                "value": "[parameters('networkPolicy')]"
            },
            "vnetSubnetID": {
                "value": "[concat(reference('deployVNET').outputs.vnetId.value,'/subnets/AKS-SN')]"
            },
            "serviceCidr": {
                "value": "[variables('serviceCidr')]"
            },
            "dnsServiceIP": {
                "value": "[variables('dnsServiceIP')]"
            },
            "dockerBridgeCidr": {
                "value": "[variables('dockerBridgeCidr')]"
            },
            "enableNodePublicIP": {
              "value": false
            }

### Azure Container Registry with Private Endpoint  
We want to provide a private Container Registry for our AKS cluster. For this we will utilize Azure Container Registry with a Private Endpoint. To deploy this through the template we'll utilize a three step process:  

1) Create the Azure Container Registry using the ACR template  

            "acrName": {
              "value": "[variables('acrName')]"
            }

2) Now that the ACR is created we can create the Private Endpoint for it using the PrivateEndpoint template  

            "peName": {
              "value": "[variables('acrName')]"
            },
            "resourceID": {
              "value": "[reference('deployACR').outputs.acrId.value]"Priv
            },
            "vnetID": {
              "value": "[reference('deployVNET').outputs.vnetId.value]"
            },
            "subnetName": {
              "value": "Data-SN"
            },
            "groupID": {
              "value": "registry"
            }  

3) Next we need to create the DNS record so we resolve to the private IP Address. We will utilize two templates for this. The PrivateDNSZone template will create the Zone and attach it to the VNet and the PrivateDNSARecord will add the A record for the newly created Private Endpoint.  

We can create the DNS Zone calling PrivateDNSZone and prividing the following:  

            "zone_name": {
              "value": "privatelink.azure.io"
            },
            "vnet_id": {
              "value": "[reference('deployVNET').outputs.vnetID.value]"
            }
          }  

To add the A record from our Private Endpoint we need to first get the IP Address of the virtual nic created by the Private Endpoint using "GetNicIP" template and then call the PrivateDNSARecord template with this value.  

First the GetNicIP we call with the following:  

          "nicID": {
            "value": "[reference('deployACRPE').outputs.nicID.value]"
          }  

Now we can execute the PrivateDNSARecord template with the following: 

           "zone_name": {
              "value": "privatelink.azure.io"
            },
            "recordname": {
              "value": "[variables('acrName')]"
            },
            "recordValue": {
              "value": "[reference('getACRNICIP').outputs.nicIP.value]"
            }

### Admin Jump Host   
In this deployment we don't have VPN access so we'll need a server in the VNet so we can do administrative work. We don't want to expose it directly to the internet so we will not create a pubic IP address. Instead we'll access it though a Bastion Host we create in the next step.  

We can deploy a Windows Server utilizing the "WindowsVirtualMachine" template and providing the following parameters:

            "subnetID": {
              "value": "[concat(reference('deployVNET').outputs.vnetId.value,'/subnets/Shared-SN')]"
            },
            "virtualMachineName": {
              "value": "[variables('jumpName')]"
            },
            "virtualMachineSize": {
              "value": "[variables('jumpSize')]"
            },
            "adminUsername": {
              "value": "[parameters('adminUserName')]"
            },
            "adminPassword": {
              "value": "[parameters('adminPassword')]"
            },
            "sku": {
              "value": "[variables('jumpSKU')]"
            }
          }  

Once the VM is deployed we want to enable VM Insights on the virtual machine using the "EnableVMInsights" template  

            "VmResourceId": {
              "value": "[reference('deployJumpBox').outputs.vmID.value]"
            },
            "osType": {
              "value": "Windows"
            },
            "WorkspaceResourceId": {
              "value": "[reference('deployLogAnalytics').outputs.workspaceId.value]"
            }

### Azure Bastion Host   
In order to access our Jump Box with no VPN or Public IP Address we will utilize the Azure Bastion service.  

We can deploy an Azure Bastion Host utilizing the "AzureBastion" template and providing the following parameters:
