describe HtmxPS {
    context 'Get-Htmx' {
        it "may help you write htmx" {
            htmx button "click me" -hx-get "api/endpoint" -hx-swap "afterend" | Should -match '\<button.+?hx-get'
        }
        it "Will treat dictionaries as attributes" {
            htmx p @{style='font-size:3em'} @{class='container'} "Hello, World!" | Should -match 'style="font-size:3em"'
        }
        it "Will treat input as content" {
            "Hello World" | htmx div hx-on:click "alert('Hello, World!')"
        }
    }
    
    context 'Start-Htmx and Stop-Htmx' {
        it "Will start and stop a small htmx server" {
            if (-not $env:GITHUB_WORKSPACE) {
                $startedLocalJob = Start-Htmx -Htmx (
                    htmx button "Click Me" hx-on:click="alert('Thanks, I needed that!')"
                )
                Invoke-RestMethod -Uri $startedLocalJob.ServerUrl
                $startedLocalJob | Stop-Htmx
                $startedLocalJob | Remove-Job
            } elseif ($env:HOSTNAME) {
                $startedLocalJob = Start-Htmx -Htmx (
                    htmx button "Click Me" hx-on:click="alert('Thanks, I needed that!')"
                ) -ServerUrl "http://$env:HOSTNAME:$(Get-Random -Min 4kb -Max 32kb)"
                Invoke-RestMethod -Uri $startedLocalJob.ServerUrl
                $startedLocalJob | Stop-Htmx
                $startedLocalJob | Remove-Job                
            } else {                
                Write-Warning "This test cannot be run without a GitHub workflow that has a host name."
            }             
        }
    }
}
