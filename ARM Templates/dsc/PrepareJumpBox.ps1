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
        [String]$rgName
    )

    Node localhost
    {
	    Script InstallTools {
            SetScript = {
                $lbIP = $using:lbIP
                $acrName = $using:acrName
                $aksName = $using:aksName
                $rgName = $using:rgName

                if((test-path HKLM:\SOFTWARE\Microsoft\DSC) -eq $false) {
                    mkdir HKLM:\SOFTWARE\Microsoft\DSC
                }
                $moduleInstalled=$null
                $modulesInstalled = Get-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\DSC -ErrorAction SilentlyContinue

                if($modulesInstalled.ModuledInstalled -ne 'True') {
                    curl https://storage.googleapis.com/kubernetes-release/release/v1.18.0/bin/windows/amd64/kubectl.exe -o C:\windows\system32\kubectl.exe
                    Invoke-WebRequest -Uri https://aka.ms/installazurecliwindows -OutFile .\AzureCLI.msi; Start-Process msiexec.exe -Wait -ArgumentList '/I AzureCLI.msi /quiet'
                    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
                    choco install kubernetes-helm --version 3.2.4 -y 
                    Install-PackageProvider -Name NuGet -RequiredVersion 2.8.5.201 -Force
                    Install-Module -Name DockerMsftProvider -Repository PSGallery -Force
                    Install-Package -Name docker -ProviderName DockerMsftProvider -Force
                    Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\DSC -Name ModuledInstalled -Value "True"

                    Restart-Computer -Force 
                }

                if((test-path c:\aksdeploy) -eq $false) {
                    mkdir c:\aksdeploy
                }
                
                curl https://raw.githubusercontent.com/bwatts64/SoutheastCSA/master/ARM%20Templates/Yaml/aks-helloworld.yaml -o C:\aksdeploy\aks-helloworld.yaml
                curl https://raw.githubusercontent.com/bwatts64/SoutheastCSA/master/ARM%20Templates/Yaml/hello-world-ingress.yaml -o C:\aksdeploy\hello-world-ingress.yaml
                curl https://raw.githubusercontent.com/bwatts64/SoutheastCSA/master/ARM%20Templates/Yaml/ingress-demo.yaml -o C:\aksdeploy\ingress-demo.yaml
                curl https://raw.githubusercontent.com/bwatts64/SoutheastCSA/master/ARM%20Templates/Yaml/internal-ingress.yaml -o C:\aksdeploy\internal-ingress.yaml

                $file = get-content C:\aksdeploy\internal-ingress.yaml
                $file -replace '#loadBalancerIP: 10.240.0.42',"loadBalancerIP: $lbIP" | out-file C:\aksdeploy\internal-ingress.yaml

                $file = get-content C:\aksdeploy\aks-helloworld.yaml
                $file -replace 'neilpeterson/aks-helloworld:v1',"$acrName/aks-helloworld:latest" | out-file C:\aksdeploy\aks-helloworld.yaml

                $file = get-content C:\aksdeploy\ingress-demo.yaml
                $file -replace 'neilpeterson/aks-helloworld:v1',"$acrName/aks-helloworld:latest" | out-file C:\aksdeploy\ingress-demo.yaml
                "Logging into Azure" | out-file c:\aksdemo\log.txt
                az login --identity

                "Getting AKS Creds" | out-file c:\aksdemo\log.txt -Append
                az aks get-credentials --resource-group testarm --name poc-AKSResource
                "Creating namespace" | out-file c:\aksdemo\log.txt -Append
                kubectl create namespace ingress-basic #Create a namespace for your ingress resources
                "Adding helm repo" | out-file c:\aksdemo\log.txt -Append
                helm repo add stable https://kubernetes-charts.storage.googleapis.com/
                "Helm install of nginx" | out-file c:\aksdemo\log.txt -Append
                helm install nginx-ingress stable/nginx-ingress --namespace ingress-basic -f C:\aksdeploy\internal-ingress.yaml --set controller.replicaCount=2 --set controller.extraArgs.enable-ssl-passthrough=""

                "ACr Login" | out-file c:\aksdemo\log.txt -Append
                az acr login --name $acrName --expose-token
                "Attach AKS to ACR" | out-file c:\aksdemo\log.txt -Append
                az aks update -n $aksName -g $rgName --attach-acr $acrName
                "Import image to ACR" | out-file c:\aksdemo\log.txt -Append
                az acr import --name $acrName --source docker.io/neilpeterson/aks-helloworld:v1 --image aks-helloworld:latest

                "Apply AKS-HellowWorld" | out-file c:\aksdemo\log.txt -Append
                kubectl apply -f C:\aksdeploy\aks-helloworld.yaml
                "Apply Ingress Demo" | out-file c:\aksdemo\log.txt -Append
                kubectl apply -f C:\aksdeploy\ingress-demo.yaml
                "Apply Internal Ingress" | out-file c:\aksdemo\log.txt -Append
                kubectl apply -f C:\aksdeploy\internal-ingress.yaml

                               
            }
            TestScript = { $false }
            GetScript = { }
        }

    }
}
