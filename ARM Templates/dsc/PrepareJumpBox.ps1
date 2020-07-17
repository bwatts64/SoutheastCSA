configuration configJumpBox
{
    Node localhost
    {
	    Script InstallTools {
            SetScript = {
                curl https://storage.googleapis.com/kubernetes-release/release/v1.18.0/bin/windows/amd64/kubectl.exe -o C:\windows\system32\kubectl.exe
                Invoke-WebRequest -Uri https://aka.ms/installazurecliwindows -OutFile .\AzureCLI.msi; Start-Process msiexec.exe -Wait -ArgumentList '/I AzureCLI.msi /quiet'
                [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
                choco install kubernetes-helm --version 3.2.4 -y                
            }
            TestScript = { $false }
            GetScript = { }
        }

    }
}
