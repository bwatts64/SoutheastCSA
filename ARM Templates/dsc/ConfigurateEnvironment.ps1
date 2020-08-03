configuration configJumpBox
{
    param
    (
        [Parameter(Mandatory)]
        [String]$lbIP,

        [Parameter(Mandatory)]
        [String]$acrName,

        [Parameter(Mandatory)]
        [String]$aksName,

        [Parameter(Mandatory)]
        [String]$gwName,

        [Parameter(Mandatory)]
        [String]$rgName
    )

    Node localhost
    {
	    Script InstallTools {
            SetScript = {
                $lbIP = $using:lbIP
                $acrName = $using:acrName
                $aksName = $using:aksName
                $gwName = $using:gwName
                $rgName = $using:rgName

                

                if((test-path c:\aksdeploy) -eq $false) {
                    mkdir aksdeploy
                }
                
                curl https://raw.githubusercontent.com/bwatts64/SoutheastCSA/master/ARM%20Templates/Yaml/ingress-demo.yaml -o ./aksdeploy/ingress-demo.yaml
                
                $file = get-content C:\aksdeploy\ingress-demo.yaml
                $file -replace 'neilpeterson/aks-helloworld:v1',"$acrName.azurecr.io/aks-helloworld:latest" | out-file C:\aksdeploy\ingress-demo.yaml
                $file -replace 'loadBalancerIP: 10.240.0.25',"loadBalancerIP: $lbIP" | out-file C:\aksdeploy\ingress-demo.yaml
                "Logging into Azure" | out-file c:\aksdeploy\log.txt
                az login --identity >> c:\aksdeploy\log.txt

                "Getting AKS Creds" | out-file c:\aksdeploy\log.txt -Append
                az aks get-credentials --resource-group testarm --name poc-AKSResource --file C:\aksdeploy\config >> c:\aksdeploy\log.txt
                "Creating namespace" | out-file c:\aksdeploy\log.txt -Append
                kubectl create namespace ingress-basic --kubeconfig C:\aksdeploy\config >> c:\aksdeploy\log.txt
                "Getting appgw" | out-file c:\aksdeploy\log.txt -Append
                az extension add --name aks-preview
                $appgwId=$(az network application-gateway show -n $gwName -g $rgName -o tsv --query "id")
                "Enabling AppGW addon" | out-file c:\aksdeploy\log.txt -Append 
                az aks enable-addons -n $aksName -g $rgName -a ingress-appgw --appgw-id $appgwId
                "ACr Login" | out-file c:\aksdeploy\log.txt -Append
                az acr login --name $acrName --expose-token >> c:\aksdeploy\log.txt
                "Attach AKS to ACR" | out-file c:\aksdeploy\log.txt -Append
                az aks update -n $aksName -g $rgName --attach-acr $acrName >> c:\aksdeploy\log.txt
                "Import image to ACR" | out-file c:\aksdeploy\log.txt -Append
                az acr import --name $acrName --source docker.io/neilpeterson/aks-helloworld:v1 --image aks-helloworld:latest >> c:\aksdeploy\log.txt

                "Apply Ingress Demo" | out-file c:\aksdeploy\log.txt -Append
                kubectl apply -f C:\aksdeploy\ingress-demo.yaml -n ingress-basic --kubeconfig C:\aksdeploy\config >> c:\aksdeploy\log.txt               
            }
            TestScript = { $false }
            GetScript = { }
        }

    }
}
