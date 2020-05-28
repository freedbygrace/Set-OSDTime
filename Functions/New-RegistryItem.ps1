Function New-RegistryItem
  {
      <#
        .SYNOPSIS
        Sets a registry value in the specified key under HKLM\Software.
   
        .DESCRIPTION 
          Sets a registry value in the specified key under HKLM\Software.
	
	
        .PARAMETER Key
          Species the registry path under HKLM\SOFTWARE\ to create.
          Defaults to OperatingSystemDeployment.


        .PARAMETER ValueName
          This parameter specifies the name of the Value to set.

        .PARAMETER Value
          This parameter specifies the value to set.
    
        .Example
           New-RegistryItem -ValueName Test -Value "abc"

        .NOTES
        -Version: 1.0
	
      #>

      [CmdletBinding()]
        Param
          (
              [Parameter(Mandatory=$True)]
              [ValidateNotNullOrEmpty()]
              [ValidateScript({($_ -imatch '^HKLM|^HKCU|^HKCR|^HKU|^HKCC|^HKPD\:\\.*$')})]
              [String]$Key,

              [Parameter(Mandatory=$True)]
              [ValidateNotNullOrEmpty()]
              [String]$ValueName,

              [Parameter(Mandatory=$False)]
              $Value,
              
              [Parameter(Mandatory=$False)]
              [ValidateScript({($_ -iin ([Microsoft.Win32.RegistryValueKind]::GetNames([Microsoft.Win32.RegistryValueKind]) | Sort-Object))})]
              [Microsoft.Win32.RegistryValueKind]$ValueType = "String",
              
              [Parameter(Mandatory=$False)]
              [Switch]$PassThru
          )
    
      Begin
        {

        }

      Process
        {      
            ##Creating the registry node
              If (!(Test-Path -Path $Key))
                {
                    $LogMessage = "Creating the registry key at `"$($Key)`""
                    Write-Verbose -Message "$($LogMessage)"
            
                    Try
                      {
                          New-Item -Path "$($Key)" -Force -ErrorAction Stop | Out-Null
                      }
                    Catch [System.Security.SecurityException]
                      {
                          $WarningMessage = "No access to the registry. Please launch this function with elevated privileges."
                          Write-Warning -Message "$($WarningMessage)"
                      }
                    Catch
                      {
                          If ([String]::IsNullOrEmpty($_.Exception.Message)) {$ExceptionMessage = "$($_.Exception.Errors.Message)"} Else {$ExceptionMessage = "$($_.Exception.Message)"}
          
                          $ErrorMessage = "[Error Message: $($ExceptionMessage)][ScriptName: $($_.InvocationInfo.ScriptName)][Line Number: $($_.InvocationInfo.ScriptLineNumber)][Line Position: $($_.InvocationInfo.OffsetInLine)][Code: $($_.InvocationInfo.Line.Trim())]"
                          Write-Error -Message "$($ErrorMessage)"
                      }
                }
              Else
                {
                    $LogMessage = "The registry key already exists at `"$($Key)`""
                    Write-Verbose -Message "$($LogMessage)"
                }

            ##Creating the registry string and setting its value
              $LogMessage = "Attempting to set registry value name `"$($ValueName)`" with a `"$($ValueType)`" value of `"$($Value)`" in `"$($Key)`". Please Wait..."
              Write-Verbose -Message "$($LogMessage)"

              Try
                {
                    New-ItemProperty -Path "$($Key)" -Name "$($ValueName)" -Value "$($Value)" -PropertyType "$($ValueType)" -Force -ErrorAction Stop | Out-Null
                }
              Catch [System.Security.SecurityException]
                {
                    $ErrorMessage = "No access to the registry. Please launch this function with elevated privileges."
                    Write-Error -Message "$($ErrorMessage)"
                }
              Catch
                {
                    If ([String]::IsNullOrEmpty($_.Exception.Message)) {$ExceptionMessage = "$($_.Exception.Errors.Message)"} Else {$ExceptionMessage = "$($_.Exception.Message)"}
          
                    $ErrorMessage = "[Error Message: $($ExceptionMessage)][ScriptName: $($_.InvocationInfo.ScriptName)][Line Number: $($_.InvocationInfo.ScriptLineNumber)][Line Position: $($_.InvocationInfo.OffsetInLine)][Code: $($_.InvocationInfo.Line.Trim())]"
                    Write-Error -Message "$($ErrorMessage)"
                }
        }

      End
        {               
              Switch ($Key)
                {
                    {$_ -imatch '^HKLM\:\\|^HKLM\:|^HKLM\\'}
                      {
                          $ConvertedKey = $Key -ireplace '(^HKLM\:\\)|(^HKLM\:)|(^HKLM\\)', 'HKEY_LOCAL_MACHINE\'
                          $KeyPath_WMIMOF = "local|$($ConvertedKey.Replace('\', '\\'))|$($ValueName)"
                      }
                    
                    {$_ -imatch '^HKCU\:\\|^HKCU\:|^HKCU\\'}
                      {
                          $ConvertedKey = $Key -ireplace '(^HKCU\:\\)|(^HKCU\:)|(^HKCU\\)', 'HKEY_CLASSES_ROOT\'
                          $KeyPath_WMIMOF = "local|$($ConvertedKey.Replace('\', '\\'))|$($ValueName)"
                      }
                    
                    {$_ -imatch '^HKCR\:\\|^HKCR\:|^HKCR\\'}
                      {
                          $ConvertedKey = $Key -ireplace '(^HKCR\:\\)|(^HKCR\:)|(^HKCR\\)', 'HKEY_CURRENT_USER\'
                          $KeyPath_WMIMOF = "local|$($ConvertedKey.Replace('\', '\\'))|$($ValueName)"
                      }
                    
                    {$_ -imatch '^HKU\:\\|^HKU\:|^HKU\\'}
                      {
                          $ConvertedKey = $Key -ireplace '(^HKU\:\\)|(^HKU\:)|(^HKU\\)', 'HKEY_USERS\'
                          $KeyPath_WMIMOF = "local|$($ConvertedKey.Replace('\', '\\'))|$($ValueName)"
                      }
                    
                    {$_ -imatch '^HKCC\:\\|^HKCC\:|^HKCC\\'}
                      {
                          $ConvertedKey = $Key -ireplace '(^HKCC\:\\)|(^HKCC\:)|(^HKCC\\)', 'HKEY_CURRENT_CONFIG\'
                          $KeyPath_WMIMOF = "local|$($ConvertedKey.Replace('\', '\\'))|$($ValueName)"
                      }
                    
                    {$_ -imatch '^HKPD\:\\|^HKPD\:|^HKPD\\'}
                      {
                          $ConvertedKey = $Key -ireplace '(^HKPD\:\\)|(^HKPD\:)|(^HKPD\\)', 'HKEY_PERFORMANCE_DATA\'
                          $KeyPath_WMIMOF = "local|$($ConvertedKey.Replace('\', '\\'))|$($ValueName)"
                      }
                } 
      
              If ($PassThru.IsPresent -eq $True)
                  {
                      $OutputObject = New-Object -TypeName 'PSobject'
                      $OutputObject | Add-Member -Name "KeyPath" -Value ($Key) -MemberType NoteProperty -Force
                      $OutputObject | Add-Member -Name "ValueName" -Value ($ValueName) -MemberType NoteProperty -Force
                      $OutputObject | Add-Member -Name "Value" -Value ($Value) -MemberType NoteProperty -Force
                      $OutputObject | Add-Member -Name "ValueType" -Value ($ValueType) -MemberType NoteProperty -Force
                      $OutputObject | Add-Member -Name "KeyPath_Regedit" -Value ($ConvertedKey) -MemberType NoteProperty -Force
                      $OutputObject | Add-Member -Name "KeyPath_WMIMOF" -Value ($KeyPath_WMIMOF) -MemberType NoteProperty -Force
                      
                      Write-Output -InputObject ($OutputObject)
                  }
        }
  }