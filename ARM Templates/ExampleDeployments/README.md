# Example Deployments  

Having all the nested templates doesn't help you unless your able to utilize them to build real world architectures. In this section we are going to focus on putting together nested templates into a real world architecture. Giving you plenty of examples and providing the expertise for you to build your own environments in simular deployments.  

## Table of Content  

* [3-Tier Applications](#3TierApplications)
     - [APIM-AKS-Azure SQL](#APIMAKSSQL)  

# <a name="3TierApplications"></a>3 Tier Applications  
Probably the most common deployment of an application is to utilize a 3 Tier Approach. For example you may have a Web Frontend, API Middle Tier, and a SQL Backend Tier.  We will walk through several 3 Tier Architectures below.  

## <a name="APIMAKSSQLPrivate"></a>API Based Application using APIM, AKS, and Azure SQL  
This architecture is made of of the following resources:  
- Virtual Network with the following Subnets  
    - AppGW-SN  
    - APIM-SN  
    - AKS-SN  
    - Data-SN  
    - Bastion-SN  
    - Management-SN  
- Application Gateway v2 with WAF and Public IP  
- APIM in Local Only Mode  
- Private AKS Cluster  
- Azure Container Registry with Private Endpoint  
- Azure Key Vault with Private Endpoint  
- Azure SQL DB with Private Endpoint  
- Azure Bastion  
- Virtual Machine  
- Azure Private DNS Zones for APIM and Private Endpoints  
- Log Analytics Workspace for Monitoring  
- Application Insights Instance for APIM and API  

<img src="./images/3-Tier-APIM-AKS-SQL.png" alt="Environment"  Width="900">  

This is an example of a privately deployed API application that is using Application Gateway as the public entry point for end users. We will secure the traffic between the subnets using Network Security Groups with the added protection of the WAF being utilized by the Application Gateway. The APIM resource will not have public access and will only be accesible via the Application Gateway or the Virtual Machine deployed on the Management Subnet. AKS, ACR, Key Vault, and Azure SQL will all utilize Private Endpoints and not allow access to their public endpoints.  

### Virtual Network Architecture  
Below we will outline the Virtual Networks and NSGs associated with them.  

#### Application Gateway Subnet  
This subnet allows public access to our APIs so we need to ensure that we protect it. We protect this subnet utilizing both a NSG and the WAF associated with the Application Gateway. The NSG will only allow traffic on port 443 for end user access and the ports needed for the Application Gateway health status. Below outlines the NSG that is created in the template.  

| Name          | Priority | Description   |  Direction     | Source/Destination Port     | Source/Destination Address  | Protocol  | 
|-------------------|-------------------|-------------------|-------------------|-------------------|-------------------|-------------------|
| Allow-443-GW          | 100 | Allow 443 Traffic Inbound from GW Subnet | Inbound  | \*\/443 | \<GW Subnet\>/\*   | TCP |
| Allow-443-Mgmt          | 110 | Allow 443 Traffic Inbound from Mgmt Subnet | Inbound  | \*\/443 | \<Mgmt Subnet\>/\*   | TCP |
| Allow-HealthProbe     | 110 | Allow the AppGW Health Status | Inbound  | \*\/65200-65535 | Azure/\* | TCP |
| Deny-All-Inbound		   | 500 | Deny All Traffic | Inbound | \*/\*   | \*/\* | TCP |  

#### APIM Subnet  
This subnet will host the APIM instance and will allow access on port 443 through the Application Gateway and the Management Subnet.  More details on the ports and protocols required for APIM can be found here: 

https://docs.microsoft.com/en-us/azure/api-management/api-management-using-with-vnet  

Below outlines the NSG that is created in the template.  

| Name          | Priority | Description   |  Direction     | Source/Destination Port     | Source/Destination Address  | Protocol  | 
|-------------------|-------------------|-------------------|-------------------|-------------------|-------------------|-------------------|
| Allow-443          | 100 | Allow 443 Traffic Inbound | Inbound  | \*\/443 | \*/\*   | TCP |
| Allow-HealthProbe     | 110 | Allow the AppGW Health Status | Inbound  | \*\/65200-65535 | Azure/\* | TCP |
| allow-azure-storage		   | 100 | Allow Azure Storage | Outbound | \*/443   | VirtualNetwork/Storage | TCP |
| allow-azure-ad		   | 110 | Allow Azure AD | Outbound | \*/443   | VirtualNetwork/AzureActiveDirectory | TCP |   
| allow-event-hub		   | 120 | Allow Azure Event Hub | Outbound | \*/5671,5672,443   | VirtualNetwork/EventHub | TCP |  
| allow-file-share		   | 130 | Allow Azure File Share | Outbound | \*/445   | VirtualNetwork/Storage | TCP |  
| allow-health-status		   | 140 | Allow Health Status | Outbound | \*/443   | VirtualNetwork/AzureCloud | TCP |  
| allow-azure-monitor		   | 150 | Allow Azure Monitor | Outbound | \*/1886,443   | VirtualNetwork/AzureMonitor | TCP |  
| allow-smtp-relay		   | 160 | Allow SMTP Relay | Outbound | \*/\24,587,25028   | VirtualNetwork/INTERNET | TCP |  
| allow-azure-cache-ib		   | 120 | Allow Azure Cache IB | Inbound | \*/6381,6382,6383   | VirtualNetwork/VirtualNetwork | TCP |  
| allow-azure-cache-ob		   | 170 | Allow Azure Cache OB | Outbound | \*/6381,6382,6383   | VirtualNetwork/VirtualNetwork | TCP |  
| allow-load-balancer		   | 130 | Allow Azure Load Balancer | Inbound | \*/\* | AzureLoadBalancer/VirtualNetwork | TCP |  
| allow-sql-endpoint		   | 180 | Allow Azure SQL | Outbound | \*/1433   | \*/VirtualNetwork | TCP |  
| allow-rate-limit-ib		   | 140 | Allow rate limit | Inbound | \*/4290   | VirtualNetwork/VirtualNetwork | TCP | 
| allow-rate-limit-ob		   | 190 | Allow rate lmit | Outbound | \*/4290   | VirtualNetwork/VirtualNetwork | TCP | 
| deny-all-ib		   | 500 | Deny all inbound traffic | Inbound | \*/\*   | \*/\* | TCP |  
| deny-all-ob		   | 500 | Deny all outbound traffic | Outbound | \*/\*   | \*/\* | TCP |  

#### AKS Subnet  
This subnet will have an empty NSG attached to it. We will utilize ingress and egress controllers within AKS to control traffic.  

#### Data Subnet  
The data subnet will only contain the virtual nics for the private endpoints. Note with these virtual network interfaces you cannot utilize NSGs to control the traffic. For this architecture we will allow any endpoint that can access the private IP to be able to connect to the private endpoint. If you needed to controll the traffic you could force tunnel all the traffic through a VNA (Virtual Network Appliance) and utilize that appliance to control the traffic. Being the only resources on this subnet are the private endpoints virtual nics we will deny all inbound and outbound traffic.   

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
          "apim-SN|192.168.1.224/28",
          "aks-SN|192.168.1.0/25",
          "data-SN|192.168.1.176/28",
          "shared-SN|192.168.1.160/28",
          "AzureBastionSubnet|192.168.1.128/28",
          "AppGW-SN|192.168.1.144/28"
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

Now that we have a virtual network and subnets we need to create and attach NSGs to them. Below I'll walk through the APIM NSG deployment. To get the APIM Address range we call "GetSubnetAddressPrefix" using the following:

            "vnetName": {
              "value": "[variables('vnetName')]"
            },
            "subnetName": {
              "value": "APIM-SN"
            }

Now that we have the address prefix for the APIM subnet we can call "NSG-ExistingSubnet" using the following:  

            "virtualNetworkName": {
              "value": "[variables('vnetName')]"
            },
            "subnetName": {
              "value": "APIM-SN"
            },
            "addressPrefix": {
              "value": "[reference('getAPIMAddressPrefix').outputs.addressPrefix.value]"
            },
            "nsgName": {
              "value": "APIM-NSG"
            },
            "securityRules": {
              "value": [
                "allow-443|Allow-SSL|Tcp|*|443|192.168.1.144/28|*|Allow|100|Inbound",
                "allow-443-mgmt|Allow-Management|Tcp|*|3443|ApiManagement|VirtualNetwork|Allow|120|Inbound",
                "allow-azure-storage|Allow-Storage-Account|Tcp|*|443|VirtualNetwork|Storage|Allow|100|Outbound",
                "allow-azure-ad|Allow-Azure-AD|Tcp|*|443|VirtualNetwork|AzureActiveDirectory|Allow|110|Outbound",
                "allow-event-hub|Allow-EventHub|Tcp|*|5671-5672|VirtualNetwork|EventHub|Allow|120|Outbound",
                "allow-event-hub-443|Allow-EventHub|Tcp|*|443|VirtualNetwork|EventHub|Allow|130|Outbound",
                "allow-file-share|Allow-FileShare|Tcp|*|445|VirtualNetwork|Storage|Allow|140|Outbound",
                "allow-health-status|Allow-Health-Status|Tcp|*|1886|VirtualNetwork|AzureCloud|Allow|150|Outbound",
                "allow-azure-monitor|Allow-Azure-Monitor|Tcp|*|443|VirtualNetwork|AzureMonitor|Allow|160|Outbound",
                "allow-azure-cache-ob|Allow-Azure-Cahce|Tcp|*|6381-6383|VirtualNetwork|VirtualNetwork|Allow|170|Outbound",
                "allow-azure-cache-ib|Allow-Azure-Cahce|Tcp|*|6381-6383|VirtualNetwork|VirtualNetwork|Allow|130|Inbound",
                "allow-rate-limit-ib|Allow-Rate-Limit-Policy|UDP|*|4290|VirtualNetwork|VirtualNetwork|Allow|140|Inbound",
                "allow-rate-limit-ob|Allow-Rate-Limit-Policy|UDP|*|4290|VirtualNetwork|VirtualNetwork|Allow|180|Outbound",
                "deny-all-inbound|Deny All|Tcp|*|*|*|*|Deny|500|Inbound",
                "deny-all-outbound|Deny All|Tcp|*|*|*|*|Deny|500|Outbound"
              ]
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

### Azure API Management Deployment  
Next we need to deploy the APIM solution in "Internal" only mode. This means that the APIM instance will not have a public access point and only be private on our APIM-SN. The only way to access the instance is from either the Application Gateway or our Jump Box.  

To deploy APIM you call the APIM template using the following:  

                "apimname": {
                    "value": "[variables('apimName')]"
                },
                "sku": {
                    "value": "[parameters('apimsku')]"
                },
                "capacity": {
                    "value": "[parameters('apimcapacity')]"
                },
                "apimEmail": {
                    "value": "[parameters('apimEmail')]"
                },
                "subnetID": {
                    "value": "[reference('deployVNET').outputs.apimSubnetID.value]"
                },
                "publisherName": {
                    "value": "[parameters('apimPublisherName')]"
                },
                "virtualNetworkType": {
                    "value": "[parameters('apimVirtualNetworkType')]"
                }  

Because we are deploying APIM in Internal mode you have to pass in the value 'Internal' for   the "virtualNetworkType" parameter.  

### AKS Deployment  
Next we will deploy our middle tier which runs AKS. The AKS cluster will be deployed privatley with no public endpoints. 
