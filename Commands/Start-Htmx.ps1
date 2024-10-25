function Start-Htmx {
    <#
    .SYNOPSIS
        Starts a small server for htmx requests.
    .DESCRIPTION
        Starts a microserver for htmxm, using PowerShell scripts.

        You can provide a htmx string, a handler scriptblock, or a route table to handle requests.

        Because htmx is fairly route-centric, this makes for a very powerful and simple way to create dynamic web pages.
    .NOTES    
        This server will create a thread job that listens for requests.  

        You should be able to see any errors encountered running a job by piping to `Receive-Job`
    .EXAMPLE
        Start-Htmx -Htmx (
            htmx h1 "Hello, World!" "-hx-on:click" "alert('Hello world')"
        ) -Route @{
            '/url' = {param($request) $request.Url.ToString() }
        }
    .EXAMPLE
        Start-Htmx -Htmx (
            htmx button -Content "ClickMe" -hx-get /RandomMessage -hx-swap afterend
        ) -Route @{
            '/RandomMessage' = { "Hello!" }
        }
    .EXAMPLE
        Start-Htmx -Htmx (
            '
            <form hx-put="/contact" hx-target="this" hx-swap="outerHTML">
            <div>
                <label>First Name</label>
                <input type="text" name="firstName" value="Joe">
            </div>
            <div class="form-group">
                <label>Last Name</label>
                <input type="text" name="lastName" value="Blow">
            </div>
            <div class="form-group">
                <label>Email Address</label>
                <input type="email" name="email" value="joe@blow.com">
            </div>
            <button class="btn">Submit</button>
            <button class="btn" hx-get="/contact/1">Cancel</button>
            </form>
            '
        ) -Route @{
            '/contact' = {
                param($firstName, $lastName, $email)
                $paramCopy = ([Ordered]@{} + $psBoundParameters)                
                @(
                    "<h1>$firstName $lastName</h1>"
                    "<p>$email</p>" 
                ) -join [Environment]::NewLine
            }
        }
    .EXAMPLE
        Start-Htmx -Htmx (
            '<button hx-get="/counter">Counter</button>'
        ) -Route @{
            '/counter' = {
                $global:MyCounter++
                "<button hx-get='/counter'>Counter $($global:MyCounter)</button>"
            }
        }
    .EXAMPLE
        Start-Htmx -Htmx @(
            htmx button "Hello, World!" "-hx-get" "/hello" "-hx-target" "#target"
            htmx div -id "target"
        ) -Palette Konsolas -Route @{
            '/hello' = { '<svg><ellipse cx="50%"" cy="50%" rx="5" ry="10" fill="currentColor"/></svg>' }
        }            
    .EXAMPLE
        Start-Htmx
    #>  
    param(
    # The root URL of the server.
    [Parameter(ValueFromPipelineByPropertyName)]
    [string]
    $ServerUrl,
       
    # The port to serve on.  
    # If this is not provided, a random port between 4kb and 32kb will be used.
    [Parameter(ValueFromPipelineByPropertyName)]
    [int]
    $Port,

    # The maximum number of background jobs to run before any has stopped.
    # (Multiple background jobs will listen for requests at multiple root URLs, as long as they don't conflict.)
    [Parameter(ValueFromPipelineByPropertyName)]
    [int]
    $ThrottleLimit = 25,

    # The default htmx content to serve.    
    [Parameter(ValueFromPipelineByPropertyName)]
    [Alias('Html')]
    [string[]]    
    $Htmx,

    # A route table for all requests.
    [Parameter(ValueFromPipelineByPropertyName)]
    [Collections.IDictionary]
    $Route,

    # The handler for all requests.  This will be used instead of `-Htmx` if no route matches.
    [Parameter(ValueFromPipelineByPropertyName)]
    [ScriptBlock]
    $Handler,

    # The lifespan of the server.  After this time, the server will stop.
    [Parameter(ValueFromPipelineByPropertyName)]
    [timespan]
    $LifeSpan,

    # The name of the palette to use.  This will include the [4bitcss](https://4bitcss.com) stylesheet.
    [Alias('Palette','ColorScheme','ColorPalette')]
    [ArgumentCompleter({
        param ($commandName,$parameterName,$wordToComplete,$commandAst,$fakeBoundParameters )
        if (-not $script:4bitcssPaletteList) {
            $script:4bitcssPaletteList = Invoke-RestMethod -Uri https://cdn.jsdelivr.net/gh/2bitdesigns/4bitcss@latest/docs/Palette-List.json
        }
        if ($wordToComplete) {
            $script:4bitcssPaletteList -match "$([Regex]::Escape($wordToComplete) -replace '\\\*', '.{0,}')"
        } else {
            $script:4bitcssPaletteList 
        }        
    })]
    [string]
    $PaletteName,

    # The [Google Font](https://fonts.google.com/) name.
    [Parameter(ValueFromPipelineByPropertyName)]
    [Alias('GoogleFont')]
    [string]
    $FontName,

    # The Google Font name to use for code blocks.
    # (this should be a [monospace font](https://fonts.google.com/?classification=Monospace))
    [Parameter(ValueFromPipelineByPropertyName)]
    [Alias('PreFont','CodeFontName','PreFontName')]
    [string]
    $CodeFont,

    # A list of javascript files or urls to include in the htmx content.
    [Parameter(ValueFromPipelineByPropertyName)]
    [string[]]
    $JavaScript,

    # A javascript import map.  This allows you to import javascript modules.
    [Parameter(ValueFromPipelineByPropertyName)]
    [Collections.IDictionary]
    $ImportMap    
    )

    begin {
        # First we define a listener job definition.
        $listenerJobDefiniton = {        
            param([Collections.IDictionary]$myParameters)
            # any parameters in the dictionary will be set as variables.
            foreach ($keyValuePair in $myParameters.GetEnumerator()) {
                $ExecutionContext.SessionState.PSVariable.Set($keyValuePair.Key, $keyValuePair.Value)
            }
            # Start the listener
            $ServerStartTime = [DateTime]::Now
            $httpListener.Start()
            # If we have routes, we will cache all of their possible parameters now
            if ($route.Count) {
                $routeParameterSets = [Ordered]@{}
                $routeParameters = [Ordered]@{}
                foreach ($routePair in $route.GetEnumerator()) {
                    $routeToCmd = 
                        if ($routePair.Value -is [ScriptBlock]) {
                            $function:TempFunction = $routePair.Value
                            $ExecutionContext.SessionState.InvokeCommand.GetCommand('TempFunction', 'Function')
                        } elseif ($routePair.Value -is [Management.Automation.CommandInfo]) {
                            $routePair.Value
                        }
                    if ($routeToCmd) {
                        $routeParameterSets[$routePair.Name] = $routeToCmd.ParametersSets
                        $routeParameters[$routePair.Name] = $routeToCmd.Parameters
                    }
                }            
            }

            # While the server is listening
            while ($httpListener.IsListening) {
                try {
                    # If the server has a lifespan, we will stop it after the lifespan has passed.
                    if (
                        $LifeSpan -is [timespan] -and 
                        $lifeSpan.TotalMilliseconds -and 
                        [DateTime]::Now -gt $ServerStartTime.Add($LifeSpan)
                    ) {
                        $httpListener.Stop()
                        break
                    }

                    # Try to get a the next context
                    $contextAsync = $httpListener.GetContextAsync()
                    $context = $contextAsync.Result
                    # and get the request and response objects from the context
                    $request, $response = $context.Request, $context.Response
                    $routedTo = $null
                    $routeKey = $null
                    # If we have routes, we will try to find a route that matches the request.                    
                    if ($route.Count) {
                        $routeTable = $route
                        $routedTo = foreach ($potentialKey in 
                            $request.Url.LocalPath,
                            ($request.Url.LocalPath -replace '/$'),
                            "$($request.HttpMethod) $($request.Url.LocalPath)",
                            "$($request.HttpMethod) $($request.Url.LocalPath -replace '/$')"
                        ) {
                            if ($routeTable[$potentialKey]) {
                                $routeTable[$potentialKey]
                                $routeKey = $potentialKey
                                break
                            }
                        }
                    }

                    # If we have no mapped route, we will try to use the handler.
                    if (-not $routedTo -and $Handler) {
                        $routedTo = $Handler
                    }
                    # If we have no mapped route, and no handler, we will try to use the htmx content.
                    elseif (-not $routedTo -and $htmx) {
                        $routedTo = 
                            # If the content is already html, we will use it as is.
                            if ($htmx -match '\<html') {
                                $htmx
                            } else {
                                # Otherwise, we will wrap it in an html tag.
                                @(
                                    "<html>"
                                    "<head>"
                                    # and apply the site header.
                                    $SiteHeader                                    
                                    "</head>"
                                    "<body>"
                                    $htmx
                                    "</body>"
                                    "</html>"
                                ) -join [Environment]::NewLine
                            }
                    }

                    # If we routed to a string, we will close the response with the string.
                    if ($routedTo -is [string]) {
                        $response.Close($OutputEncoding.GetBytes($routedTo), $true)
                        continue
                    }
                    
                    # If we routed to a script block or command, we will try to execute it.
                    if ($routedTo -is [ScriptBlock] -or 
                        $routedTo -is [Management.Automation.CommandInfo]) {                        
                        $routeSplat = [Ordered]@{}

                        # If the command had a `-Request` parameter, we will pass the request object.
                        if ($routeParameters -and $routeParameters[$routeKey].Request) {
                            $routeSplat['Request'] = $request
                        }
                        # If the command had a `-Response` parameter, we will pass the response object.
                        if ($routeParameters -and $routeParameters[$routeKey].Response) {
                            $routeSplat['Response'] = $response
                        }

                        # If the request has a query string, we will parse it and pass the values to the command.
                        if ($request.Url.QueryString) {
                            $parsedQuery = [Web.HttpUtility]::ParseQueryString($request.Url.QueryString)
                            foreach ($parsedQueryKey in $parsedQuery.Keys) {
                                if ($routeParameters[$routeKey][$parsedQueryKey]) {
                                    $routeSplat[$parsedQueryKey] = $parsedQuery[$parsedQueryKey]
                                }
                            }
                        }
                        # If the request has a content type of json, we will parse the json and pass the values to the command.
                        if ($request.ContentType -eq 'application/json') {
                            $streamReader = [IO.StreamReader]::new($request.InputStream)
                            $json = $streamReader.ReadToEnd()
                            $jsonHashtable = ConvertFrom-Json -InputObject $json -AsHashtable
                            foreach ($keyValuePair in $jsonHashtable.GetEnumerator()) {
                                if ($routeParameters[$routeKey][$keyValuePair.Key]) {
                                    $routeSplat[$keyValuePair.Key] = $keyValuePair.Value
                                }
                            }
                            $streamReader.Close()
                            $streamReader.Dispose()                        
                        }

                        # If the request has a content type of form-urlencoded, we will parse the form and pass the values to the command.
                        if ($request.ContentType -eq 'application/x-www-form-urlencoded') {
                            $streamReader = [IO.StreamReader]::new($request.InputStream)
                            $form = [Web.HttpUtility]::ParseQueryString($streamReader.ReadToEnd())
                            foreach ($formKey in $form.Keys) {
                                if ($routeParameters[$routeKey][$formKey]) {
                                    $routeSplat[$formKey] = $form[$formKey]
                                }
                            }
                            $streamReader.Close()
                            $streamReader.Dispose()
                        }

                        # We will execute the command and get the output.
                        $routeOutput = . $routedTo @routeSplat
                        
                        # If the output is a string, we will close the response with the string.
                        if ($routeOutput -is [string]) 
                        {                        
                            $response.Close($OutputEncoding.GetBytes($routeOutput), $true)
                            continue
                        }
                        # If the output is a byte array, we will close the response with the byte array.
                        elseif ($routeOutput -is [byte[]]) 
                        {
                            $response.Close($routeOutput, $true)
                            continue
                        }
                        # If the response is an array, write the responses out one at a time.
                        # (note: this will likely be changed in the future)
                        elseif ($routeOutput -is [object[]]) {
                            foreach ($routeOut in $routeOutput) {                                
                                if ($routeOut -is [string]) {                                    
                                    $routeOut = $OutputEncoding.GetBytes($routeOut)
                                }
                                if ($routeOut -is [byte[]]) {
                                    $response.OutputStream.Write($routeOut, 0, $routeOut.Length)
                                }
                            }
                            $response.Close()
                        }
                        else {
                            # If the response was an object, we will convert it to json and close the response with the json.
                            $responseJson = ConvertTo-Json -InputObject $routeOutput -Depth 3
                            $response.ContentType = 'application/json'
                            $response.Close($OutputEncoding.GetBytes($responseJson), $true)
                        }
                    }
                } catch {
                    # If we caught any errors, we will write them out. (use `Receive-Job` to see them)
                    Write-Error $_
                }
            }
        }
    }

    process {
        # First, copy our parameters
        $myParams = [Ordered]@{} + $PSBoundParameters
        # then we determine a default server URL
        if (-not $myParams['ServerUrl']) {
            $ServerUrl = $myParams['ServerUrl'] =
                if (-not $ServerUrl) {
                    # If we are on unix, and a port has not been set, 
                    # and an environment variable indicates we are in a container, we will use port 80.
                    if ($PSVersionTable.Platform -eq 'Unix' -and (
                        Get-ChildItem env: | Where-Object Name -Match InContainer
                    )) {
                        if (-not $port) { $port = 80 }
                        "http://*:$port/"
                    } else {
                        # If we are on Windows, we will use a random port between 4kb and 32kb.
                        if (-not $port) { $port = $(Get-Random -Min 4kb -Max 32kb)}
                        "http://localhost:$port/"
                    }
                } else {
                    $ServerUrl
                }
        }
        
        # If we have no idea where to serve, we will return now.
        if (-not $myParams['ServerUrl']) {
            return
        }

        # Create a new listener
        $httpListener = [Net.HttpListener]::new()
        # and add our prefixes.
        $httpListener.Prefixes.Add($ServerUrl)
        
        # If we have any routes, now is the time to do the hard work of mapping parameters
        if ($Route) {
            # We'll keep track of both parameter sets
            $routeParameterSets = [Ordered]@{}
            # and route parameters
            $routeParameters = [Ordered]@{}
            foreach ($routePair in $Route.GetEnumerator()) {
                $routeToCmd = 
                    if ($routePair.Value -is [ScriptBlock]) {
                        # If the route is a script block, we will create a function from it.
                        $function:TempFunction = $routePair.Value
                        $ExecutionContext.SessionState.InvokeCommand.GetCommand('TempFunction', 'Function')
                    } elseif ($routePair.Value -is [Management.Automation.CommandInfo]) {
                        $routePair.Value
                    }
                # If we have successfully resolved a route to a command, just get the parameter sets and parameters.
                if ($routeToCmd) {
                    $routeParameterSets[$routePair.Name] = $routeToCmd.ParametersSets
                    $routeParameters[$routePair.Name] = $routeToCmd.Parameters
                }
            }

            $myParams['RouteParameterSets'] = $routeParameterSets
            $myParams['RouteParameters'] = $routeParameters
        }
        
        # Now we create the default site header.
        # this will be used if no <html> tag is found in the content.
        $myParams['SiteHeader'] = @(
            # We will always include the lastest htmx library.
            "<script src='https://unpkg.com/htmx.org@latest'></script>"
            if ($Javascript) {
                # as well as any javascript files provided.
                foreach ($jsFile in $Javascript) {
                    "<script src='$javascript'></script>"
                }
            }
                  
            # If an import map was provided, we will include it.
            if ($ImportMap) {                
                $myParams['ImportMap'] = @(
                    "<script type='importmap'>"
                    [Ordered]@{
                        imports = $ImportMap
                    } | ConvertTo-Json -Depth 3
                    "</script>"
                ) -join [Environment]::NewLine                
            }

            # If a palette name was provided, we will include the 4bitcss stylesheet.
            if ($PaletteName) {
                '<link type="text/css" rel="stylesheet" href="https://cdn.jsdelivr.net/gh/2bitdesigns/4bitcss@latest/css/.css" id="4bitcss" />' -replace '\.css', "$PaletteName.css"
            }
            # If a code font was provided, we will include the code font stylesheet.
            if ($CodeFont) {
                "<link type='text/css' rel='stylesheet' href='https://fonts.googleapis.com/css?family=$CodeFont' id='codefont' />"
            }
            # If a font name was provided, we will include the font stylesheet.
            if ($FontName) {
                "<link type='text/css' rel='stylesheet' href='https://fonts.googleapis.com/css?family=$FontName' id='fontname' />"
            }
            
            # and if any stylesheets were provided, we will include them.
            if ($myParams.StyleSheet) {
                foreach ($cssLink in $myParams.StyleSheet) {
                    if ($cssLink -is [string] -or $cssLink -is [uri]) {
                        "<link rel='stylesheet' href='$cssLink' />"
                    }
                }
            }
        )
        
        # Now we copy everything onto the listener object
        $myParams['HttpListener'] = $httpListener

        # We will create a job name from the listener prefixes.
        $jobName = $httpListener.Prefixes -join ';' -replace 
            'https?://' -replace 'localhost' -replace 
            '^', ($MyInvocation.InvocationName -replace '^.+?\p{P}' -replace '$',':/')

        # And we will start the listener in a thread job.
        $serverJob = Start-ThreadJob -ScriptBlock $listenerJobDefiniton -ArgumentList $myParams -Name $jobName -ThrottleLimit $ThrottleLimit 
        

        # Add all of our parameters to the job object.
        foreach ($keyValuePair in $myParams.GetEnumerator()) {
            $serverJob.psobject.properties.add(
                [psnoteproperty]::new($keyValuePair.Key, $keyValuePair.Value), $true
            )        
        }
        
        # If we haven't determined the server URL, we will do so now.
        if (-not $serverJob.ServerUrl) {
            $prefixes = $HttpListener.Prefixes -as [string[]]        
            $ServerUrl = $prefixes[0]
            $serverJob.psobject.properties.add(
                [psnoteproperty]::new('ServerUrl', $ServerUrl), $true
            )
        }
        
        $serverJob
    }
}
