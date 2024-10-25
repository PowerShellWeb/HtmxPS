[ValidatePattern('Stop\p{P}+Htmx')]
param()
function Stop-Htmx {
    <#
    
    .SYNOPSIS    
        Stops an htmx server.    
    .DESCRIPTION    
        Stops an htmx server running in a background job.    
    
    #>
            

    param(
    [Parameter(ParameterSetName='JobParameterSet', Mandatory=$true, Position=0, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
    [ValidateNotNullOrEmpty()]
    [System.Management.Automation.Job[]]
    ${Job},

    [switch]
    ${PassThru},

    [Parameter(ParameterSetName='NameParameterSet', Mandatory=$true, Position=0, ValueFromPipelineByPropertyName=$true)]
    [ValidateNotNullOrEmpty()]
    [string[]]
    ${Name},

    [Parameter(ParameterSetName='InstanceIdParameterSet', Mandatory=$true, Position=0, ValueFromPipelineByPropertyName=$true)]
    [ValidateNotNullOrEmpty()]
    [guid[]]
    ${InstanceId},

    [Parameter(ParameterSetName='SessionIdParameterSet', Mandatory=$true, Position=0, ValueFromPipelineByPropertyName=$true)]
    [ValidateNotNullOrEmpty()]
    [int[]]
    ${Id},

    [Parameter(ParameterSetName='StateParameterSet', Mandatory=$true, Position=0, ValueFromPipelineByPropertyName=$true)]
    [System.Management.Automation.JobState]
    ${State},

    [Parameter(ParameterSetName='FilterParameterSet', Mandatory=$true, Position=0, ValueFromPipelineByPropertyName=$true)]
    [ValidateNotNullOrEmpty()]
    [hashtable]
    ${Filter}
    )
    dynamicParam {
    $baseCommand = 
        if (-not $script:StopJob) {
            $script:StopJob = 
                $executionContext.SessionState.InvokeCommand.GetCommand('Stop-Job','Cmdlet')
            $script:StopJob
        } else {
            $script:StopJob
        }
    $IncludeParameter = @()
    $ExcludeParameter = @()

    }
        process {
        if ($job) {
            if ($job.HttpListener) {
                $job.HttpListener.Stop()
            }
            $job | Stop-Job -PassThru:$passThru
        } else {
            foreach ($existingJob in Get-Job @PSBoundParameters) {
                if ($existingJob.HttpListener) {
                    try {
                        $existingJob.HttpListener.Stop()
                    } catch {
                        Write-Verbose "Failed to stop the listener for job $($existingJob.Id): $_"
                    }
                    
                }
                $existingJob | Stop-Job -PassThru:$passThru
            }
        }
    
    }
}

