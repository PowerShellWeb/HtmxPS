[ValidatePattern('Stop\p{P}+Htmx')]
param()
function Stop-Htmx {
    <#
    .SYNOPSIS
        Stops an htmx server.
    .DESCRIPTION
        Stops an htmx server running in a background job.
    #>
    [inherit('Stop-Job', Abstract)]
    param()

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
