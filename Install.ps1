function Install-PowerShell7AndWinget {
    <#
    .SYNOPSIS
        Installs PowerShell 7 and Winget on a Windows machine.
    #>
    param ()

    function Test-WingetInstalled {
        return Get-Command winget -ErrorAction SilentlyContinue
    }

    Write-Output "Checking if Winget is installed..."
    $wingetInstalled = Test-WingetInstalled

    if (-not $wingetInstalled) {
        Write-Output "Winget is not installed. Installing Winget..."
        # Download the latest Winget installer
        Invoke-WebRequest -Uri https://aka.ms/getwinget -OutFile "$env:TEMP\winget.msixbundle"

        # Install Winget
        Add-AppxPackage -Path "$env:TEMP\winget.msixbundle"

        # Clean up the installer file
        Remove-Item "$env:TEMP\winget.msixbundle"

        Write-Output "Winget installation completed."

        # Retry mechanism to ensure Winget is recognized
        $maxRetries = 5
        $retryCount = 0
        do {
            Start-Sleep -Seconds 5
            $wingetInstalled = Test-WingetInstalled
            $retryCount++
        } while (-not $wingetInstalled -and $retryCount -lt $maxRetries)

        if (-not $wingetInstalled) {
            Write-Error "Winget installation failed or Winget is not recognized after installation."
            return
        }
    }
    else {
        Write-Output "Winget is already installed."
    }

    Write-Output "Checking if PowerShell 7 is installed..."
    $pwshInstalled = Get-Command pwsh -ErrorAction SilentlyContinue

    if (-not $pwshInstalled) {
        Write-Output "PowerShell 7 is not installed. Installing PowerShell 7 using Winget..."
        Start-Process winget -ArgumentList "install --id Microsoft.Powershell --source winget --accept-source-agreements --accept-package-agreements --silent" -Wait
        Write-Output "PowerShell 7 installation completed."
    }
    else {
        Write-Output "PowerShell 7 is already installed."
    }
}

Write-Output "Installing necessary tools..."
# Call the Install-PowerShell7AndWinget function
Install-PowerShell7AndWinget
