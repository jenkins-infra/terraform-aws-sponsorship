version: 1.1
tasks:
- task: executeScript
  inputs:
  - frequency: always
    type: powershell
    runAs: localSystem
    content: |-
      ## Set up permissions context (as you are Administrator here)
      Set-ExecutionPolicy Unrestricted -Scope LocalMachine -Force -ErrorAction Ignore
      # Don't set this before Set-ExecutionPolicy as it throws an error
      $ErrorActionPreference = "stop"

      ## Custom functions to manipulate environment variables
      function AddToPathEnv {
        param (
          $path
        )
        Write-Host "Adding $path to the PATH environment variable..."
        $oldPath = (Get-ItemProperty -Path 'Registry::HKEY_LOCAL_MACHINE\System\CurrentControlSet\Control\Session Manager\Environment' -Name PATH).path
        $newPath = '{0};{1}' -f $path,$oldPath
        Set-ItemProperty -Path 'Registry::HKEY_LOCAL_MACHINE\System\CurrentControlSet\Control\Session Manager\Environment' -Name PATH -Value $newPath | Out-Null
        # Update self (script) environment
        $env:Path = $newPath
      }

      function AddEnvToSystem {
        param (
          $name,
          $value
        )

        Write-Host "Adding $name environment variable to system with the value $value..."
        New-ItemProperty -Path 'Registry::HKEY_LOCAL_MACHINE\System\CurrentControlSet\Control\Session Manager\Environment' -Name $name -Value $value | Out-Null
        # Update self (script) environment
        Set-Item "env:$name" $value
      }

      ## Set up custom environment (usually defined on agent templates with EC2/Azure VMs/Kubernetes Jenkins plugins)
      ## Note: must be performed before jenkins user opens its SSH session so it's picked up by agent.jar process
      AddEnvToSystem -name 'JAVA_HOME' -value '${java_home}'
      AddToPathEnv -path '${java_home}/bin'
      AddEnvToSystem -name 'ARTIFACT_CACHING_PROXY_SERVERID' -value '${acp_url}'
      Get-Date

      ## Setup datadog
      (Get-Content C:\ProgramData\Datadog\datadog.yaml -Raw) -Replace 'api_key:', 'api_key: ${datadog_api_key}' | Set-Content C:\ProgramData\Datadog\datadog.yaml
      Add-Content -Path C:\ProgramData\Datadog\datadog.yaml -Value "tags: [`"jenkins_controller:${ci_fqdn}`", `"jenkins_agent_type:ephemeral_ec2`", `"jenkins_agent_description:${description}`"]"
      & "$env:ProgramFiles\Datadog\Datadog Agent\bin\agent.exe" restart-service
      Write-Output 'Datadog service setup'
      Get-Date

      ## Disable WinRM
      Remove-Item -Path WSMan:\Localhost\listener\listener* -Recurse
      cmd.exe /c net stop winrm
      Write-Output 'WinRM disabled'
      Get-Date

      ## Setup NVMe(s) and map it to the Z: drive
      $nb = Get-Disk | Where-Object PartitionStyle -eq 'RAW' | tee -Variable Disks | measure
      Write-Output "$nb.Count disk found."
      Get-Date
      Switch ($nb.Count)
      {
        0 {Write-Output "No RAW disk found."}
        1 {
            $Disks | Initialize-Disk -PartitionStyle MBR
            $Disks | New-Partition -UseMaximumSize -MbrType IFS
            $Partition = Get-Partition -DiskNumber $Disks.Number
            $Partition | Format-Volume -FileSystem NTFS -Confirm:$false
            $Partition | Add-PartitionAccessPath -AccessPath "Z:"
            Get-WmiObject Win32_Volume | Format-Table Name, Label, FreeSpace, Capacity
        }
        default {
            $Disks | ForEach-Object -Begin {Get-Date} -Process {
                    Initialize-Disk -PartitionStyle MBR -PassThru -DiskNumber $_.Number
                    New-Partition -UseMaximumSize -MbrType IFS
                    $Partition = Get-Partition -DiskNumber $_.Number
                    $Partition | Format-Volume -FileSystem NTFS -Confirm:$false
                    $Partition | Add-PartitionAccessPath -AccessPath "Z:"
                } -End {Get-Date}
            Get-WmiObject Win32_Volume | Format-Table Name, Label, FreeSpace, Capacity
        }
      }
      Write-Output 'Disk setup finished.'
      Get-Date

      ## Setup Docker Engine (allowing both admin and non-admin users)
      $dockerGroup = 'docker-users'
      try {Get-LocalGroup -Name $dockerGroup;} catch {New-LocalGroup -Name $dockerGroup;}

      # Note: file path MUST use Unix-style separator (/)
      @"
      {
        "hosts": ["npipe://"],
        "data-root": "Z:/docker",
        "group": "$dockerGroup"
      }
      "@ | Set-Content C:\ProgramData\Docker\config\daemon.json
      # Restart docker engine
      Restart-Service docker
      docker info
      Write-Output 'Docker Engine setup finished.'
      Get-Date

      # Enable Developer mode to allow creating symlinks for non-admin users
      reg add "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock" /v "AllowDevelopmentWithoutDevLicense" /t REG_DWORD /d 1 /f

      # Set up Windows default Users profiles location to the custom data disk drive
      $userpath = 'Z:\Users'
      $regpath = 'HKLM:\Software\Microsoft\Windows NT\CurrentVersion\ProfileList'
      $regname = 'ProfilesDirectory'
      Set-ItemProperty -path $regpath -name $regname -value $userpath
      Write-Output "Set up default user profiles to $userpath"

      # Create the 'jenkins' agent's user account
      $username = 'jenkins'
      ## TODO: generate random password
      $userPassword = 'J3nkinsSuperSecret1234!'
      $pw = ConvertTo-SecureString -String $userPassword -AsPlainText -Force
      New-LocalUser -Name $username -Password $pw

      $sshGroup = "openssh users"
      try {Get-LocalGroup -Name $sshGroup;} catch {New-LocalGroup -Name $sshGroup;}

      Add-LocalGroupMember -Group $sshGroup -Member $username
      Add-LocalGroupMember -Group $dockerGroup -Member $username

      Write-Output "User $username created."
      Get-Date

      ## Ensure User Profile and CryptoAPI seed generator are initialized
      ## User Profile: ensures the userhome and userprofile are all in the same drive (C: or Z: based on setup)
      ## CryptoAPI seed generator: requires a password SSH/WinRM/powershell non-interactive session
      ## See https://github.com/PowerShell/Win32-OpenSSH/discussions/2420 and https://github.com/jenkinsci/credentials-plugin/pull/999
      $env:DISPLAY = '0'
      $env:SSH_ASKPASS_REQUIRE = 'force'
      $env:SSH_ASKPASS = 'C:\askpass.bat'
      @"
      @echo off
      echo $userPassword
      "@ | Set-Content $env:SSH_ASKPASS
      echo 'java.security.SecureRandom.getInstanceStrong().generateSeed(1)' | ssh $username@localhost -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null "${java_home}\bin\jshell.exe"
      Remove-Item -Path "$env:SSH_ASKPASS" -Force
      Write-Output 'Initialized User Profile and CryptoAPI through SSH with password authentication'
      Get-Date

      # Setup SSH key for user in its profile (as it is non admin) reusing the same key
      # Must be done only AFTER setting up the "CryptoAPI" seed generator to ensure agent does not connect too early (e.g. before user profile or seed generator initialization)
      $userSSHDir = "$userpath\$username\.ssh"
      New-Item -ItemType Directory -Path "$userSSHDir" -Force | Out-Null
      Copy-Item -Path "C:\ProgramData\ssh\administrators_authorized_keys" -Destination "$userSSHDir\authorized_keys"
      Get-Date

      ## Retrieve Maven cache from S3 bucket
      New-Item -ItemType Directory -Path C:/cache
      aws s3 cp s3://ci-jenkins-io-maven-cache/maven-bom-local-repo.tar.gz C:/cache/
      Get-Date

      ## Mark cloud init as finished using a marker file
      New-Item -Path "Z:/Temp" -ItemType "Directory"
      New-Item -Path "Z:/Temp/.cloud-init.done" -ItemType "File" -Value "Cloud Init"
