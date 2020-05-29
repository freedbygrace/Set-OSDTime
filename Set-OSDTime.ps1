#Requires -Version 3

<#
    .SYNOPSIS
    A script that can be used with Microsoft Deployment Toolkit or SCCM to allow for the collection, storage, and retrieval of deployment timestamps
          
    .DESCRIPTION
    Gets the timestamps corrected and standardized during deployment to avoid incorrect timestamps due to synchronization, WindowsPE default time zone issues, etc.
          
    .PARAMETER OSDVariablePrefix
    Any valid string that ends with an underscore will be used as the attribute prefix.
    If you create a task sequence during operating system deployment and prefix the task sequence variable name with what is specified in this parameter, that task sequence variable will be dynamically detected by this script and included as part of information recorded within WMI or the registry without additional modification of this script.
    This parameter will be validated using a regular expression to ensure that the string ends with an underscore and is formatted like the following. Example: "MyOSDVariablePrefix_"

    .PARAMETER Start
    Sets the script to start mode so that the starting timestamp can be created. This must be run FIRST as a prerequisite in order for the end mode to execute successfully. You have been warned!

    .PARAMETER OSDVariableName_Start
    The name of the task sequence variable that you want to contain the value of your deployment start time.

    .PARAMETER End
    Sets the script to start mode so that the ending timestamp can be created.

    .PARAMETER OSDVariableName_End
    The name of the task sequence variable that you want to contain the value of your deployment end time.

    .PARAMETER DestinationTimeZoneID
    A valid string. Specify a time zone ID that exists on the current system. Input will be validated against the list of time zones available on the system.
    All date/time operations within this script will convert the current system time to the destination timezone for standardization.

    .PARAMETER FinalConversionTimeZoneID
    A valid string. Specify a time zone ID that exists on the current system. Input will be validated against the list of time zones available on the system.
    All date/time operations within this script will convert the timestamps to the final conversion timezone ID. UTC by default.

    .PARAMETER PerformTimeSynchronization
    Your parameter description

    .PARAMETER NTPServerFQDN
    The FQDN of the Network Time Protocol server (NTP)

    .PARAMETER Services
    Any relevant services that need to started during this operation. This will not really need to modified or specified in most cases. This parameter is only here for flexibility.

    .PARAMETER LogDir
    A valid folder path. If the folder does not exist, it will be created. This parameter can also be specified by the alias "LogPath".

    .PARAMETER ContinueOnError
    Ignore failures.
          
    .EXAMPLE
    powershell.exe -ExecutionPolicy Bypass -NoProfile -NoLogo -File "%FolderPathContainingScript%\Set-OSDTime.ps1" -Start -OSDVariablePrefix "CustomOSDInfo_" -$OSDVariableName_Start "OSDStartTime" -DestinationTimeZoneID "Eastern Standard Time" -SyncTime -LogDir "%_SMSTSLogPath%\Set-OSDTime"

    .EXAMPLE
    powershell.exe -ExecutionPolicy Bypass -NoProfile -NoLogo -File "%FolderPathContainingScript%\Set-OSDTime.ps1" -End -OSDVariablePrefix "CustomOSDInfo_" -$OSDVariableName_Start "OSDEndTime" -DestinationTimeZoneID "Eastern Standard Time" -SyncTime -LogDir "%_SMSTSLogPath%\Set-OSDTime"

    .EXAMPLE
    powershell.exe -ExecutionPolicy Bypass -NoProfile -NoLogo -File "%FolderPathContainingScript%\Set-OSDTime.ps1" -SyncTime -Start

    .EXAMPLE
    powershell.exe -ExecutionPolicy Bypass -NoProfile -NoLogo -File "%FolderPathContainingScript%\Set-OSDTime.ps1" -SyncTime -End
  
    .NOTES
    Another script will be released that will be able to take parts of this data and record it into the registry and into WMI (Look for Set-OSDInformation)
          
    .LINK
    www.powershellDistrict.com

    .LINK
    https://github.com/Stephanevg/Manage-OSDTime

    .LINK
    https://github.com/freedbygrace/Set-OSDTime

    .LINK
    https://haralambos.wordpress.com/2018/08/14/time-sync-during-osd-in-winpe-mdt/

    .LINK
    https://www.windows-noob.com/forums/topic/11016-how-can-i-sync-the-bios-date-in-winpe-to-avoid-pxe-boot-failure-with-system-center-2012-r2-configuration-manager/page/2/
#>

[CmdletBinding()]
    Param
        (        	     
            [Parameter(Mandatory=$False)]
            [ValidateNotNullOrEmpty()]
            [ValidateScript({($_ -imatch '^.*\_$')})]
            [String]$OSDVariablePrefix = "CustomOSDInfo_",
            
            [Parameter(Mandatory=$False)]
            [Switch]$Start,

            [Parameter(Mandatory=$False)]
            [ValidateNotNullOrEmpty()]
            [String]$OSDVariableName_Start = "$($OSDVariablePrefix)OSDStartTime",

            [Parameter(Mandatory=$False)]
            [Switch]$End,

            [Parameter(Mandatory=$False)]
            [ValidateNotNullOrEmpty()]
            [String]$OSDVariableName_End = "$($OSDVariablePrefix)OSDEndTime",

            [Parameter(Mandatory=$False)]
            [Alias('SyncTime')]
            [Switch]$PerformTimeSynchronization,

            [Parameter(Mandatory=$False)]
            [ValidateNotNullOrEmpty()]
            [Alias('NTPServer')]
            [String]$NTPServerFQDN = "pool.ntp.org",
            
            [Parameter(Mandatory=$False)]
            [ValidateNotNullOrEmpty()]
            [ValidateScript({($_ -iin ([System.TimeZoneInfo]::GetSystemTimeZones().ID | Sort-Object))})]
            [String]$DestinationTimeZoneID = "Eastern Standard Time",

            [Parameter(Mandatory=$False)]
            [ValidateNotNullOrEmpty()]
            [ValidateScript({($_ -iin ([System.TimeZoneInfo]::GetSystemTimeZones().ID | Sort-Object))})]
            [String]$FinalConversionTimeZoneID = "UTC",
            
            [Parameter(Mandatory=$False)]
            [ValidateNotNullOrEmpty()]
            [String[]]$Services = "w32time",
            
            [Parameter(Mandatory=$False)]
            [ValidateNotNullOrEmpty()]
            [ValidateScript({($_ -imatch '^[a-zA-Z][\:]\\.*?[^\\]$')})]
            [Alias('LogPath')]
            [System.IO.DirectoryInfo]$LogDir = "$($Env:Windir)\Logs\Software\Set-OSDTime",
            
            [Parameter(Mandatory=$False)]
            [Switch]$ContinueOnError
        )

#Define Default Action Preferences
    $Script:DebugPreference = 'SilentlyContinue'
    $Script:ErrorActionPreference = 'Stop'
    $Script:VerbosePreference = 'SilentlyContinue'
    $Script:WarningPreference = 'Continue'
    $Script:ConfirmPreference = 'None'
    
#Load WMI Classes
  $Baseboard = Get-WmiObject -Namespace "root\CIMv2" -Class "Win32_Baseboard" -Property * | Select-Object -Property *
  $Bios = Get-WmiObject -Namespace "root\CIMv2" -Class "Win32_Bios" -Property * | Select-Object -Property *
  $ComputerSystem = Get-WmiObject -Namespace "root\CIMv2" -Class "Win32_ComputerSystem" -Property * | Select-Object -Property *
  $OperatingSystem = Get-WmiObject -Namespace "root\CIMv2" -Class "Win32_OperatingSystem" -Property * | Select-Object -Property *

#Retrieve property values
  $OSArchitecture = $($OperatingSystem.OSArchitecture).Replace("-bit", "").Replace("32", "86").Insert(0,"x").ToUpper()

#Define variable(s)
  $DateTimeLogFormat = 'dddd, MMMM dd, yyyy hh:mm:ss tt'  ###Monday, January 01, 2019 10:15:34 AM###
  [ScriptBlock]$GetCurrentDateTimeLogFormat = {(Get-Date).ToString($DateTimeLogFormat)}
  $DateTimeFileFormat = 'yyyyMMdd_hhmmsstt'  ###20190403_115354AM###
  [ScriptBlock]$GetCurrentDateTimeFileFormat = {(Get-Date).ToString($DateTimeFileFormat)}
  [System.IO.FileInfo]$ScriptPath = "$($MyInvocation.MyCommand.Definition)"
  [System.IO.FileInfo]$ScriptLogPath = "$($LogDir.FullName)\$($ScriptPath.BaseName)_$($GetCurrentDateTimeFileFormat.Invoke()).log"
  [System.IO.DirectoryInfo]$ScriptDirectory = "$($ScriptPath.Directory.FullName)"
  [System.IO.DirectoryInfo]$FunctionsDirectory = "$($ScriptDirectory.FullName)\Functions"
  [System.IO.DirectoryInfo]$ModulesDirectory = "$($ScriptDirectory.FullName)\Modules"
  [System.IO.DirectoryInfo]$ToolsDirectory = "$($ScriptDirectory.FullName)\Tools\$($OSArchitecture)"
  $IsWindowsPE = Test-Path -Path 'HKLM:\SYSTEM\ControlSet001\Control\MiniNT' -ErrorAction SilentlyContinue

#Log any useful information
  $LogMessage = "IsWindowsPE = $($IsWindowsPE.ToString())`r`n"
  Write-Verbose -Message "$($LogMessage)" -Verbose

  $LogMessage = "Script Path = $($ScriptPath.FullName)`r`n"
  Write-Verbose -Message "$($LogMessage)" -Verbose
  
  $LogMessage = "Script Directory = $($ScriptDirectory.FullName)`r`n"
  Write-Verbose -Message "$($LogMessage)" -Verbose
	
#Log task sequence variables if debug mode is enabled within the task sequence
  Try
    {
        [System.__ComObject]$TSEnvironment = New-Object -ComObject "Microsoft.SMS.TSEnvironment"
              
        If ($TSEnvironment -ine $Null)
          {
              $IsRunningTaskSequence = $True
          }
    }
  Catch
    {
        $IsRunningTaskSequence = $False
    }

#Start transcripting (Logging)
  Try
    {
        If ($LogDir.Exists -eq $False) {[Void][System.IO.Directory]::CreateDirectory($LogDir.FullName)}
        Start-Transcript -Path "$($ScriptLogPath.FullName)" -IncludeInvocationHeader -Force -Verbose
    }
  Catch
    {
        If ([String]::IsNullOrEmpty($_.Exception.Message)) {$ExceptionMessage = "$($_.Exception.Errors.Message)"} Else {$ExceptionMessage = "$($_.Exception.Message)"}
          
        $ErrorMessage = "[Error Message: $($ExceptionMessage)][ScriptName: $($_.InvocationInfo.ScriptName)][Line Number: $($_.InvocationInfo.ScriptLineNumber)][Line Position: $($_.InvocationInfo.OffsetInLine)][Code: $($_.InvocationInfo.Line.Trim())]"
        Write-Error -Message "$($ErrorMessage)"
    }

#Log any useful information
  $LogMessage = "IsWindowsPE = $($IsWindowsPE.ToString())"
  Write-Verbose -Message "$($LogMessage)" -Verbose

  $LogMessage = "Script Path = $($ScriptPath.FullName)"
  Write-Verbose -Message "$($LogMessage)" -Verbose

  $DirectoryVariables = Get-Variable | Where-Object {($_.Value -ine $Null) -and ($_.Value -is [System.IO.DirectoryInfo])}
  
  ForEach ($DirectoryVariable In $DirectoryVariables)
    {
        $LogMessage = "$($DirectoryVariable.Name) = $($DirectoryVariable.Value.FullName)"
        Write-Verbose -Message "$($LogMessage)" -Verbose
    }

#region Import Dependency Modules
$Modules = Get-Module -Name "$($ModulesDirectory.FullName)\*" -ListAvailable -ErrorAction Stop 

$ModuleGroups = $Modules | Group-Object -Property @('Name')

ForEach ($ModuleGroup In $ModuleGroups)
  {
      $LatestModuleVersion = $ModuleGroup.Group | Sort-Object -Property @('Version') -Descending | Select-Object -First 1
      
      If ($LatestModuleVersion -ine $Null)
        {
            $LogMessage = "Attempting to import dependency powershell module `"$($LatestModuleVersion.Name) [Version: $($LatestModuleVersion.Version.ToString())]`". Please Wait..."
            Write-Verbose -Message "$($LogMessage)" -Verbose
            Import-Module -Name "$($LatestModuleVersion.Path)" -Global -DisableNameChecking -Force -ErrorAction Stop
        }
  }
#endregion

#region Dot Source Dependency Scripts
#Dot source any additional script(s) from the functions directory. This will provide flexibility to add additional functions without adding complexity to the main script and to maintain function consistency.
  Try
    {
        If ($FunctionsDirectory.Exists -eq $True)
          {
              [String[]]$AdditionalFunctionsFilter = "*.ps1"
        
              $AdditionalFunctionsToImport = Get-ChildItem -Path "$($FunctionsDirectory.FullName)" -Include ($AdditionalFunctionsFilter) -Recurse -Force | Where-Object {($_ -is [System.IO.FileInfo])}
        
              $AdditionalFunctionsToImportCount = $AdditionalFunctionsToImport | Measure-Object | Select-Object -ExpandProperty Count
        
              If ($AdditionalFunctionsToImportCount -gt 0)
                {                    
                    ForEach ($AdditionalFunctionToImport In $AdditionalFunctionsToImport)
                      {
                          Try
                            {
                                $LogMessage = "Attempting to dot source dependency script `"$($AdditionalFunctionToImport.Name)`". Please Wait...`r`n`r`nScript Path: `"$($AdditionalFunctionToImport.FullName)`""
                                Write-Verbose -Message "$($LogMessage)" -Verbose
                          
                                . "$($AdditionalFunctionToImport.FullName)"
                            }
                          Catch
                            {
                                $ErrorMessage = "[Error Message: $($_.Exception.Message)]`r`n`r`n[ScriptName: $($_.InvocationInfo.ScriptName)]`r`n[Line Number: $($_.InvocationInfo.ScriptLineNumber)]`r`n[Line Position: $($_.InvocationInfo.OffsetInLine)]`r`n[Code: $($_.InvocationInfo.Line.Trim())]"
                                Write-Error -Message "$($ErrorMessage)" -Verbose
                            }
                      }
                }
          }
    }
  Catch
    {
        $ErrorMessage = "[Error Message: $($_.Exception.Message)]`r`n`r`n[ScriptName: $($_.InvocationInfo.ScriptName)]`r`n[Line Number: $($_.InvocationInfo.ScriptLineNumber)]`r`n[Line Position: $($_.InvocationInfo.OffsetInLine)]`r`n[Code: $($_.InvocationInfo.Line.Trim())]"
        Write-Error -Message "$($ErrorMessage)" -Verbose            
    }
#endregion

#Perform script action(s)
  Try
    {                          
        #Tasks defined within this block will only execute if a task sequence is running
          If (($IsRunningTaskSequence -eq $True))
            {                    
                $OriginalTimeZone = Get-TimeZone
                $DestinationTimeZone = Get-TimeZone -ID "$($DestinationTimeZoneID)"
                $FinalConversionTimeZone = Get-TimeZone -ID "$($FinalConversionTimeZoneID)"
                                    
                $LogMessage = "The current time zone set in the operating system is `"$($OriginalTimeZone.DisplayName)`""
                Write-Verbose -Message "$($LogMessage)" -Verbose
 
                #Usually a time synchronization is required from WindowsPE to avoid incorrect time stamps (The code below provides a method to address this issue by allowing the client to synchronize with a network time protocol (NTP) server)
                  If (($PerformTimeSynchronization.IsPresent -eq $True))
                    {                      
                        $IsNTPServerOnline = Test-Connection -ComputerName "$($NTPServerFQDN)" -Count 1 -Quiet
                      
                        If ($IsNTPServerOnline -eq $True)
                          {
                              $LogMessage = "Successfully contacted the network time protocol (NTP) server - [Server: $($NTPServerFQDN)]"
                              Write-Verbose -Message "$($LogMessage)" -Verbose
                          }
                        Else
                          {
                              $WarningMessage = "Unable to contact the network time protocol (NTP) server - [Server: $($NTPServerFQDN)]"
                              Write-Warning -Message "$($WarningMessage)" -Verbose
                          }
                            
                        If ($IsWindowsPE -eq $True)
                          {
                              $LogMessage = "[WindowsPE Detected] - [Version: $($OperatingSystem.Version.ToString())] - Additional file(s), system settings, and registry changes are required to allow time synchronization to occur."
                              Write-Verbose -Message "$($LogMessage)" -Verbose
                          
                              [System.IO.DirectoryInfo]$Path_w32tm = "$($ToolsDirectory.FullName)\w32tm"
                              $GetFiles_w32tm = Get-ChildItem -Path "$($Path_w32tm.FullName)" -Recurse -Force | Where-Object {($_ -is [System.IO.FileInfo])}
                            
                              ForEach ($File In $GetFiles_w32tm)
                                {
                                    If ($File.Directory.FullName.EndsWith("$($Path_w32tm.Name)") -eq $True)
                                      {
                                          [System.IO.FileInfo]$DestinationPath = "$([System.Environment]::SystemDirectory)\$($File.Name)"
                                      }
                                    Else
                                      {
                                          [System.IO.FileInfo]$DestinationPath = "$([System.Environment]::SystemDirectory)\$($File.Directory.Name)\$($File.Name)"
                                      }

                                    If ($DestinationPath.Exists -eq $False)
                                      {
                                          If ($DestinationPath.Directory.Exists -eq $False) {[Void][System.IO.Directory]::CreateDirectory($DestinationPath.Directory.FullName)}
                                          Copy-Item -Path "$($File.FullName)" -Destination "$($DestinationPath.Directory.FullName)\" -Force -Verbose
                                      }
                                }
                          
                              New-RegistryItem -Key "HKLM:\Software\ControlSet001\Services\W32Time\Config" -ValueName "MaxPosPhaseCorrection" -Value "0xFFFFFFFF" -ValueType DWord -Verbose
                              New-RegistryItem -Key "HKLM:\Software\ControlSet001\Services\W32Time\Config" -ValueName "MaxNegPhaseCorrection" -Value "0xFFFFFFFF" -ValueType DWord -Verbose
                              
                              $LogMessage = "Time Before Time Zone Adjustment: $((Get-Date).ToString($DateTimeLogFormat)) - [$($OriginalTimeZone.DisplayName)]"
                              Write-Verbose -Message "$($LogMessage)" -Verbose
                    
                              $LogMessage = "Attempting to change the current time zone from `"$($OriginalTimeZone.DisplayName)`" to `"$($DestinationTimeZone.DisplayName)`". Please Wait..."
                              Write-Verbose -Message "$($LogMessage)" -Verbose
                      
                              If ($OriginalTimeZone.ID -ine $DestinationTimeZoneID) {$SetTimeZone = Set-TimeZone -Id "$($DestinationTimeZone.ID)" -PassThru}
                          }
                        Else
                          {
                              $LogMessage = "[WindowsPE Not Detected] - No additional changes are required to allow time synchronization to occur."
                              Write-Verbose -Message "$($LogMessage)" -Verbose

                              $LogMessage = "[Current Operating System] - $($OperatingSystem.Caption -ireplace "(Microsoft)\s", '') [Version: $($OperatingSystem.Version.ToString())]"
                              Write-Verbose -Message "$($LogMessage)" -Verbose
                          }
                                           
                        $LogMessage = "Time Before NTP Synchronization: $((Get-Date).ToString($DateTimeLogFormat)) - [$($DestinationTimeZone.DisplayName)]"
                        Write-Verbose -Message "$($LogMessage)" -Verbose
                            
                        ForEach ($Service In $Services)
                          {
                              Try
                                {
                                    $ServiceProperties = Get-Service -Name "$($Service)"

                                    If (($ServiceProperties.Status -inotmatch "Running"))
                                      {
                                          $LogMessage = "Now performing configuration of the `"$($ServiceProperties.Name)`" service [DisplayName: $($ServiceProperties.DisplayName)]. Please Wait..."
                                          Write-Verbose -Message "$($LogMessage)" -Verbose

                                          If ($ServiceProperties.Status -inotmatch "Running") {Set-Service -Name "$($Service)" -Status Running -Verbose}
                                      }
                                }
                              Catch
                                {
                                    If ([String]::IsNullOrEmpty($_.Exception.Message)) {$ExceptionMessage = "$($_.Exception.Errors.Message)"} Else {$ExceptionMessage = "$($_.Exception.Message)"}
          
                                    $ErrorMessage = "[Error Message: $($ExceptionMessage)][ScriptName: $($_.InvocationInfo.ScriptName)][Line Number: $($_.InvocationInfo.ScriptLineNumber)][Line Position: $($_.InvocationInfo.OffsetInLine)][Code: $($_.InvocationInfo.Line.Trim())]"
                                    Write-Error -Message "$($ErrorMessage)"
                                }
                          }
                                                                        
                        [System.IO.FileInfo]$BinaryPath = "$([System.Environment]::SystemDirectory)\w32tm.exe"
                        [String]$BinaryParameters = "/config /manualpeerlist:`"$($NTPServerFQDN)`" /syncfromflags:MANUAL /update"
                        [System.IO.FileInfo]$BinaryStandardOutputPath = "$($LogDir.FullName)\$($BinaryPath.BaseName)_StandardOutput.log"
                        [System.IO.FileInfo]$BinaryStandardErrorPath = "$($LogDir.FullName)\$($BinaryPath.BaseName)_StandardError.log"
                                            
                        If ($BinaryPath.Exists -eq $True)
                          {
                              $LogMessage = "Attempting to perform a time synchronization against `"$($NTPServerFQDN)`". Please Wait..."
                              Write-Verbose -Message "$($LogMessage)" -Verbose
                        
                              $LogMessage = "Binary Path - [$($BinaryPath.FullName)]"
                              Write-Verbose -Message "$($LogMessage)" -Verbose

                              $LogMessage = "Binary Parameters - [$($BinaryParameters)]"
                              Write-Verbose -Message "$($LogMessage)" -Verbose
                            
                              $LogMessage = "Binary Standard Output Path - [$($BinaryStandardOutputPath.FullName)]"
                              Write-Verbose -Message "$($LogMessage)" -Verbose
                            
                              $LogMessage = "Binary Standard Error Path - [$($BinaryStandardErrorPath.FullName)]"
                              Write-Verbose -Message "$($LogMessage)" -Verbose
                            
                              $ExecuteBinary = Start-Process -FilePath "$($BinaryPath.FullName)" -ArgumentList "$($BinaryParameters)" -WindowStyle Hidden -Wait -RedirectStandardOutput "$($BinaryStandardOutputPath.FullName)" -RedirectStandardError "$($BinaryStandardErrorPath.FullName)" -PassThru
                            
                              [Int[]]$AcceptableExitCodes = @('0', '3010')
                        
                              If ($ExecuteBinary.ExitCode -iin $AcceptableExitCodes)
                                {
                                    $LogMessage = "Binary Execution Success - [Exit Code: $($ExecuteBinary.ExitCode.ToString())]"
                                    Write-Verbose -Message "$($LogMessage)" -Verbose

                                    $BinaryStandardOutput = Get-Content -Path "$($BinaryStandardOutputPath.FullName)" -Raw -Force
                                                  
                                    $LogMessage = "Binary Standard Output - [$($BinaryPath.Name)]`r`n$($BinaryStandardOutput.ToString())"
                                    Write-Verbose -Message "$($LogMessage)" -Verbose
   
                                    Stop-Service -Name ($Services) -Force -Verbose
                                        
                                    Start-Service -Name ($Services) -Verbose
                                        
                                    [Int]$Seconds = 20
                                    $LogMessage = "Pausing script execution for $($Seconds.ToString()) seconds. Please Wait..."
                                    Write-Verbose -Message "$($LogMessage)" -Verbose
                  
                                    Start-Sleep -Seconds $Seconds
                                  
                                    $LogMessage = "Time After NTP Synchronization: $((Get-Date).ToString($DateTimeLogFormat)) - [$($DestinationTimeZone.DisplayName)]"
                                    Write-Verbose -Message "$($LogMessage)" -Verbose
                                }
                              Else
                                {
                                    $ErrorMessage = "Binary Execution Error - [Exit Code: $($ExecuteBinary.ExitCode.ToString())]"
                                    Write-Error -Message "$($ErrorMessage)" -Verbose

                                    $BinaryErrorOutput = Get-Content -Path "$($BinaryStandardErrorPath.FullName)" -Raw -Force
                                                  
                                    $ErrorMessage = "Binary Error Output - [$($BinaryPath.Name)]`r`n$($BinaryErrorOutput.ToString())"
                                    Write-Error -Message "$($ErrorMessage)" -Verbose
                                }
                          }
                    }
                                      
                If ($Start.IsPresent -eq $True)
                  {
                      #Create Original Time Zone Variable
                        $OSDOriginalTimeZoneIDVariableName = "$($OSDVariablePrefix)OSDOriginalTimeZoneID"
                        
                        $TSEnvironment.Value($OSDOriginalTimeZoneIDVariableName) = "$($OriginalTimeZone.ID)"
                            
                        $LogMessage = "The task sequence conversion time zone variable `"$($OSDOriginalTimeZoneIDVariableName)`" is now set to `"$($TSEnvironment.Value($OSDOriginalTimeZoneIDVariableName))`"."
                        Write-Verbose -Message "$($LogMessage)" -Verbose

                      #Create Destination Time Zone Variable
                        $OSDDestinationTimeZoneIDVariableName = "$($OSDVariablePrefix)OSDDestinationTimeZoneID"
                        
                        $TSEnvironment.Value($OSDDestinationTimeZoneIDVariableName) = "$($DestinationTimeZone.ID)"
                            
                        $LogMessage = "The task sequence destination time zone variable `"$($OSDDestinationTimeZoneIDVariableName)`" is now set to `"$($TSEnvironment.Value($OSDDestinationTimeZoneIDVariableName))`"."
                        Write-Verbose -Message "$($LogMessage)" -Verbose    
                
                      #Create Conversion Time Zone Variable
                        $OSDConversionTimeZoneIDVariableName = "$($OSDVariablePrefix)OSDConversionTimeZoneID"
                        
                        $TSEnvironment.Value($OSDConversionTimeZoneIDVariableName) = "$($FinalConversionTimeZone.ID)"
                            
                        $LogMessage = "The task sequence conversion time zone variable `"$($OSDConversionTimeZoneIDVariableName)`" is now set to `"$($TSEnvironment.Value($OSDConversionTimeZoneIDVariableName))`"."
                        Write-Verbose -Message "$($LogMessage)" -Verbose
                      
                      $LogMessage = "Attempting to convert the current system time to `"$($DestinationTimeZone.DisplayName)`". Please Wait..."
                      Write-Verbose -Message "$($LogMessage)" -Verbose
                  
                      [DateTime]$ConvertedSystemDateTime = [System.TimeZoneInfo]::ConvertTimeBySystemTimeZoneId((Get-Date), ($DestinationTimeZoneID))
                      
                      $LogMessage = "Attempting to convert the current system time into `"$($FinalConversionTimeZone.DisplayName)`". Please Wait..."
                      Write-Verbose -Message "$($LogMessage)" -Verbose
                      
                      [DateTime]$ConvertedSystemDateTimeUTC = $ConvertedSystemDateTime.ToUniversalTime()
                  
                      [DateTime]$StartTime = $ConvertedSystemDateTimeUTC
                      
                      $TSEnvironment.Value($OSDVariableName_Start) = $StartTime
                      
                      [DateTime]$TaskSequenceStartTime = Get-Date -Date "$($TSEnvironment.Value($OSDVariableName_Start))"
          
                      $LogMessage = "The task sequence start time variable `"$($OSDVariableName_Start)`" is now set to $($TaskSequenceStartTime.ToString($DateTimeLogFormat)) - [$($FinalConversionTimeZone.DisplayName)] - The task sequence variable value was formatted for logging purposes."
                      Write-Verbose -Message "$($LogMessage)" -Verbose   
                  }
                ElseIf ($End.IsPresent -eq $True)
                  { 
                      $StartTime = $TSEnvironment.Value($OSDVariableName_Start)
                      
                      If ($StartTime -ieq $Null)
                        {
                            $WarningMessage = "Could not find the Task sequence variable `"$($OSDVariableName_Start)`". The `"$($ScriptPath.Name)`" script needs to be executed at least one with the -Start switch. - [Example: $($ScriptPath.FullName) -Start]"
                            Write-Warning -Message "$($WarningMessage)" -Verbose
                        }
                      Else
                        {                
                            [DateTime]$TaskSequenceStartTime = Get-Date -Date "$($StartTime)"
                            
                            $LogMessage = "The currently running task sequence was started on $($TaskSequenceStartTime.ToString($DateTimeLogFormat)) - [$($FinalConversionTimeZone.DisplayName)]."
                            Write-Verbose -Message "$($LogMessage)" -Verbose
                
                            $LogMessage = "Attempting to convert the current system time to `"$($DestinationTimeZone.DisplayName)`". Please Wait..."
                            Write-Verbose -Message "$($LogMessage)" -Verbose
                  
                            [DateTime]$ConvertedSystemDateTime = [System.TimeZoneInfo]::ConvertTimeBySystemTimeZoneId((Get-Date), ($DestinationTimeZoneID))
                      
                            $LogMessage = "Attempting to convert the current system time into `"$($FinalConversionTimeZone.DisplayName)`". Please Wait..."
                            Write-Verbose -Message "$($LogMessage)" -Verbose
                      
                            [DateTime]$ConvertedSystemDateTimeUTC = $ConvertedSystemDateTime.ToUniversalTime()
                        
                            [DateTime]$EndTime = $ConvertedSystemDateTimeUTC
                            
                            $TSEnvironment.Value($OSDVariableName_End) = $EndTime
                            
                            [DateTime]$TaskSequenceEndTime = Get-Date -Date "$($TSEnvironment.Value($OSDVariableName_End))"
                                
                            $LogMessage = "The task sequence end time variable `"$($OSDVariableName_End)`" is now set to $($TaskSequenceEndTime.ToString($DateTimeLogFormat)) - [$($FinalConversionTimeZone.DisplayName)] - The task sequence variable value was formatted for logging purposes."
                            Write-Verbose -Message "$($LogMessage)" -Verbose
                                                        
                            #Total deployment time
                              [Timespan]$TaskSequenceTotalTimespan = New-TimeSpan -Start ($StartTime) -End ($EndTime)
                            
                              [String]$TaskSequenceTotalTime = "$($TaskSequenceTotalTimespan.Hours.ToString()) hours, $($TaskSequenceTotalTimespan.Minutes.ToString()) minutes, $($TaskSequenceTotalTimespan.Seconds.ToString()) seconds, and $($TaskSequenceTotalTimespan.Milliseconds.ToString()) milliseconds"
                            
                              $OSDTotalTimeVariableName = "$($OSDVariablePrefix)OSDTotalTime"
                        
                              $TSEnvironment.Value($OSDTotalTimeVariableName) = $TaskSequenceTotalTime
                                                        
                              $LogMessage = "The task sequence total time variable `"$($OSDTotalTimeVariableName)`" is now set to `"$($TSEnvironment.Value($OSDTotalTimeVariableName))`"."
                              Write-Verbose -Message "$($LogMessage)" -Verbose
                        
                              $LogMessage = "The task sequence has taken [$($TaskSequenceTotalTime)] to complete."
                              Write-Verbose -Message "$($LogMessage)" -Verbose
                        }
                  }     
            }
    
        #Tasks defined here will execute whether only if a task sequence is not running
          If ($IsRunningTaskSequence -eq $False)
            {
                $WarningMessage = "There is no task sequence running.`r`n"
                Write-Warning -Message "$($WarningMessage)" -Verbose
            }
                        
        #Stop transcripting (Logging)
          Try
            {
                Stop-Transcript -Verbose
            }
          Catch
            {
                If ([String]::IsNullOrEmpty($_.Exception.Message)) {$ExceptionMessage = "$($_.Exception.Errors.Message)"} Else {$ExceptionMessage = "$($_.Exception.Message)"}
          
                $ErrorMessage = "[Error Message: $($ExceptionMessage)][ScriptName: $($_.InvocationInfo.ScriptName)][Line Number: $($_.InvocationInfo.ScriptLineNumber)][Line Position: $($_.InvocationInfo.OffsetInLine)][Code: $($_.InvocationInfo.Line.Trim())]"
                Write-Error -Message "$($ErrorMessage)"
            }
    }
  Catch
    {
        If ([String]::IsNullOrEmpty($_.Exception.Message)) {$ExceptionMessage = "$($_.Exception.Errors.Message -Join "`r`n`r`n")"} Else {$ExceptionMessage = "$($_.Exception.Message)"}
          
        $ErrorMessage = "[Error Message: $($ExceptionMessage)]`r`n`r`n[ScriptName: $($_.InvocationInfo.ScriptName)]`r`n[Line Number: $($_.InvocationInfo.ScriptLineNumber)]`r`n[Line Position: $($_.InvocationInfo.OffsetInLine)]`r`n[Code: $($_.InvocationInfo.Line.Trim())]`r`n"
        If ($ContinueOnError.IsPresent -eq $False) {Throw "$($ErrorMessage)"}
    }