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
}
