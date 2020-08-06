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
        [String]$rgName,

        [Parameter(Mandatory)]
        [String]$saName,

        [Parameter(Mandatory)]
        [String]$aiKey,

        [Parameter(Mandatory)]
        [String]$sqlName,

        [Parameter(Mandatory)]
        [String]$dbName,

        [Parameter(Mandatory)]
        [String]$sqlAdmin,

        [Parameter(Mandatory)]
        [SecureString]$sqlPwd
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
                $saName = $using:saName
                $aiKey = $using:aiKey
                $sqlName = $using:sqlName
                $dbName = $using:dbName
                $sqlAdmin = $using:sqlAdmin
                $sqlPwd = $using:sqlPwd

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

                $sqlPwd = $sqlPwd | convertfrom-securestring

                if((test-path c:\aksdeploy) -eq $false) {
                    mkdir aksdeploy
                }
                
                curl https://raw.githubusercontent.com/bwatts64/SoutheastCSA/master/ARM%20Templates/Yaml/secrets.yaml -o c:\aksdeploy\secrets.yaml
                curl https://raw.githubusercontent.com/bwatts64/SoutheastCSA/master/ARM%20Templates/Yaml/backend.yaml -o c:\aksdeploy\backend.yaml
                curl https://raw.githubusercontent.com/bwatts64/SoutheastCSA/master/ARM%20Templates/Yaml/frontend.yaml -o c:\aksdeploy\frontend.yaml
                curl https://raw.githubusercontent.com/bwatts64/SoutheastCSA/master/ARM%20Templates/Yaml/services.yaml -o c:\aksdeploy\services.yaml
                curl https://raw.githubusercontent.com/bwatts64/SoutheastCSA/master/ARM%20Templates/SQL/dbbackup.bacpac -o c:\aksdeploy\dbbackup.bacpac

                $aiKey = Get-AzApplicationInsightsApiKey -
                $saKey = (Get-AzStorageAccountKey -ResourceGroupName $rgName -AccountName $saName)[0].Value
                # Place bacpac file in storage
                $file = "c:\aksdeploy\dbbackup.bacpac"
                $storageAccount = Get-AzStorageAccount -ResourceGroupName $rgName -Name $saName
                $ctx = $storageAccount.Context
                $containerName = "sqlbackup"
                New-AzStorageContainer -Name $containerName -Context $ctx -Permission blob
                Set-AzStorageBlobContent -File "c:\aksdeploy\dbbackup.bacpac" -Container $containerName -Blob "dbbackup.bacpac" -Context $ctx

                $db = Get-AzSqlDatabase -ResourceGroupName testarm -DatabaseName $dbName -ServerName $sqlName
                $edition = $db.Edition


                $dbConnectionString="Server=tcp:$sqlName.database.windows.net,1433;Initial Catalog=$dbName;Persist Security Info=False;User ID=azureuser;Password=$sqlPwd;MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
                $dbConnectionString | out-file c:\aksdeploy\log.txt

                $b64Connection = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($dbConnectionString))
                $b64saName = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($saName))
                $b64saKey = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($saKey))
                $b64aiKey = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($aiKey))

                
                $file = get-content c:\aksdeploy\secrets.yaml
                $file -replace '<CONNECTIONSTRING>',"$b64Connection" | out-file c:\aksdeploy\secrets.yaml
                $file = get-content c:\aksdeploy\secrets.yaml
                $file -replace '<SAKEY>',"$b64saKey" | out-file c:\aksdeploy\secrets.yaml
                $file = get-content c:\aksdeploy\secrets.yaml
                $file -replace '<SANAME>',"$b64saName" | out-file c:\aksdeploy\secrets.yaml
                $file = get-content c:\aksdeploy\secrets.yaml
                $file -replace '<AIKEY>',"$b64aiKey" | out-file c:\aksdeploy\secrets.yaml

                $file = get-content c:\aksdeploy\backend.yaml
                $file -replace '<ACRNAME>',"$acrName" | out-file c:\aksdeploy\backend.yaml

                $file = get-content c:\aksdeploy\frontend.yaml
                $file -replace '<ACRNAME>',"$acrName" | out-file c:\aksdeploy\frontend.yaml

                $file = get-content c:\aksdeploy\services.yaml
                $file -replace '<LBIP>',"$lbIP" | out-file c:\aksdeploy\services.yaml

                "Getting AKS Creds" | out-file c:\aksdeploy\log.txt -Append
                az aks get-credentials --resource-group testarm --name poc-AKSResource --file c:\aksdeploy\config >> c:\aksdeploy\log.txt
                "Creating namespace" | out-file c:\aksdeploy\log.txt -Append
                kubectl create namespace ingress-basic --kubeconfig c:\aksdeploy\config >> c:\aksdeploy\log.txt
                "ACr Login" | out-file c:\aksdeploy\log.txt -Append
                az acr login --name $acrName --expose-token >> c:\aksdeploy\log.txt
                "Attach AKS to ACR" | out-file c:\aksdeploy\log.txt -Append
                az aks update -n $aksName -g $rgName --attach-acr $acrName >> c:\aksdeploy\log.txt
                "Import image to ACR" | out-file c:\aksdeploy\log.txt -Append
                az acr import --name $acrName --source docker.io/bwatts64/frontend:latest --image frontend:latest >> c:\aksdeploy\log.txt
                az acr import --name $acrName --source docker.io/bwatts64/sessions-cleaner:latest --image sessions-cleaner:latest >> c:\aksdeploy\log.txt
                az acr import --name $acrName --source docker.io/bwatts64/votings:latest --image votings:latest >> c:\aksdeploy\log.txt
                az acr import --name $acrName --source docker.io/bwatts64/sessions:latest --image sessions:latest >> c:\aksdeploy\log.txt


                $saURI="$($storageAccount.Context.BlobEndPoint)sqlbackup/dbbackup.bacpac"
                New-AzSqlDatabaseImport -ResourceGroupName $rgName -ServerName $sqlName -DatabaseName $dbName -StorageKeyType "StorageAccessKey" -StorageKey $saKey -StorageUri $saURI -AdministratorLogin $sqlAdmin -AdministratorLoginPassword $sqlPwd -Edition $edition -ServiceObjectiveName S0 

                kubectl apply -f c:\aksdeploy\secrets.yaml -n ingress-basic --kubeconfig c:\aksdeploy\config >> c:\aksdeploy\log.txt
                kubectl apply -f c:\aksdeploy\frontend.yaml -n ingress-basic --kubeconfig c:\aksdeploy\config >> c:\aksdeploy\log.txt
                kubectl apply -f c:\aksdeploy\backend.yaml -n ingress-basic --kubeconfig c:\aksdeploy\config >> c:\aksdeploy\log.txt
                kubectl apply -f c:\aksdeploy\services.yaml -n ingress-basic --kubeconfig c:\aksdeploy\config >> c:\aksdeploy\log.txt
            }
            TestScript = { $false }
            GetScript = { }
        }

    }
}
