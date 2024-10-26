function Get-HTMX {
    <#
    .SYNOPSIS
        Creates HTMX tags in PowerShell.
    .DESCRIPTION
        Get-Htmx is a freeform function that creates HTML tags in PowerShell.
        
        The function has no explicit parameters.

        Instead, broadly speaking, arguments become attributes (unless it appears to be a tag or has whitespace) and inputs become children.        
    .NOTES
        Ideally, this command is very forgiving in its input and helps you write HTMX tag in PowerShell.

        If this proves not to be the case, feel free to open an issue.

        The function determines which parameters are treated as attributes through several checks:

        1. Piped input will always be treated as child elements.
        2. If the argument is a dictionary, its key-value pairs are treated as attributes.
        3. If the argument is a string containing an equals sign (e.g., "key=value"), it is split into a key and value, and added as an attribute.
        4. If an argument is a string and does not match certain patterns (e.g., it does not look like a tag or an attribute), it is used as the tag name.
        5. If an argument is whitespace or a colon/equals sign, it is skipped.
        6. If an attribute key is detected without a value, the next argument is treated as its value.
        7. If the last key is content, child, or children, the argument is treated as a child element.                 
    .EXAMPLE
        Get-Htmx div class=container "Hello, World!"
    .EXAMPLE
        htmx button "Click Me" hx-on:click="alert('Thanks, I needed that!')"
    #>
    [ArgumentCompleter({
        param(
            $wordToComplete,
            $commandAst,
            $cursorPosition
        )        
    })]

    param()

    # Collect all input       
    $allInput = @($input)
    # and any arguments
    $allArguments = @($args)
    # Unroll any arguments:  any collections are expanded to their elements
    $unrolledArguments = @($allArguments | . { process { $_ } })
    # Create a list of child elements
    $moreChildren = [Collections.Generic.List[Object]]::new()
    # Add all input to the list of child elements
    $moreChildren.AddRange($allInput)
    
    # Create a collection of attributes
    $attributes = [Ordered]@{}
    
    # And a list of all future content.
    $allContent = [Collections.Generic.List[Object]]::new()
    $allContent.AddRange($allInput)
    
    # Capture the invocation information, as it will be easier to debug with it.
    $myInv = $MyInvocation

    # If this function is called any other name, we will use that name as the tag name.
    # To do this, we use a relatively simple pattern.
    # Put in english, instead of Regex, it is:
    # * Optionally Match Get, followed by one or more punctuation characters
    # * Match HTMX, followed by zero or more punctuation characters
    $getHtmxPrefixPattern = '(?>Get\p{P}+)?HTMX[\p{P}]{0,}'
    $myName = $MyInvocation.InvocationName -replace $getHtmxPrefixPattern
    
    # Now we walk over each argument and determine if it is an attribute or content.
    foreach ($argument in $unrolledArguments) {

        # Starting easy, if the argument is a dictionary, we will treat it as attributes.
        if ($argument -is [Collections.IDictionary]) {
            foreach ($key in $argument.Keys) {
                $attributes[$key] = $argument[$key]
            }
            continue
        }

        # If the argument is a string, and we have not yet determined the tag name, we will use it.
        if (
            -not $myName -and
            $argument -is [string] -and 
            # provided, of course, that it does not look like a tag or an attribute
            $argument -notmatch '[\p{P}\<\>\s-[\-]]' -and $argument -notmatch '^hx-'
        ) {
            $myName = $argument
            continue
        }
        
        
        # If the argument is _only_ whitespace and a colon or equals sign, we will skip it.
        if ($argument -is [string] -and 
            $argument -match '^\s{0,}[=:]\s{0,}$') {
            continue
        }

        # If the argument has a equals sign, surrounded by content, we will treat it as an attribute.
        if ($argument -is [string] -and $argument -match '^.+?=.+?$') {
            $key, $value = $argument -split '=', 2
            $attributes[$key] = $value
            continue
        }

        # If the argument is a tag, we will add it to the content.
        if ($argument -match '[\<\>]') {
            $allContent.Add($argument)
            continue
        }

        # If we have any attribute without a value, we will treat the next argument as the value.
        if ($attributes.Count -and $null -eq $attributes[-1]) {
            $lastKey = @($attributes.Keys)[-1]
            # If the last key is content, child, or children, we will treat the argument as a child.
            if ($lastKey -in 'content', 'child', 'children') {
                $moreChildren.Add($argument)
                $attributes.Remove($lastKey)
            } else {
                # Otherwise, we will treat it as a value.
                $attributes[@($attributes.Keys)[-1]] = $argument
            }
            
        } else {
            # Otherwise, if the argument is whitespace, we will add it to the content.
            if ($argument -match '[\s\r\n]') {
                $allContent.Add($argument)
            } else {
                # and if it does not we will treat it as an attribute name.
                $attributes[$argument -replace '^[\p{P}]+'] = $null
            }
        }            
    }
    

    # If we have no attributes and no children, we will return the module.
    if (-not $attributes.Count -and -not $moreChildren.Count) {        
        return $HtmxPS
    }

    # Otherwise, we will create the tag.
    $ElementName = if ($myName) { $myName } else { "html" }
    
    @(            
        "<$ElementName"
        # We will walk over each attribute and create the attribute string.
        foreach ($attr in $attributes.GetEnumerator()) {
            if (-not $attr.Key) { continue }
            if (-not [String]::IsNullOrEmpty($attr.Value)) {
                " $($attr.Key)=`"$([Web.HttpUtility]::HtmlAttributeEncode($attr.Value))`""
            } else {
                " $($attr.Key)"
            }
        }
    
        # If we do not have children, we can close the tag now.
        if (-not $moreChildren) { ' />'}
        # Otherwise, we will close the tag after the children.
        else { '>'}
    
        if ($moreChildren) {
            @(
                # We will walk over each child and create the child string.
                foreach ($contentItem in $moreChildren) {
                    # If the content has a `ToHtml` method, we will use it.
                    if ($contentItem.ToHtml.Invoke) {
                        $contentItem.ToHtml()
                    } elseif ($contentItem.Html) {
                        # Otherwise, we will look for an `Html` property.
                        $contentItem.Html
                    }                      
                    elseif ($contentItem.outerHTML) {
                        # Or an `outerHTML` property.
                        $contentItem.outerHTML                        
                    } elseif ($contentItem.OuterXML) {
                        # Or an `OuterXML` property.
                        $contentItem.OuterXML
                    } else {
                        # If none of those are available, we will use the content as is.
                        $contentItem
                    }
                }
                "</$ElementName>"                  
            ) -join ''
        }
    ) -join ''        
}

# We have to register argument completers for the command and it's noun.
$commandName = 'Get-HTMX'
$CommandNameAndAliases = @(
    $commandName
    if ($commandName -match '^Get\p{P}+') {
        $($commandName -replace 'Get\p{P}+')
    }
)
# we do this by taking the argument completer attribute on ourself
foreach ($attributes in $ExecutionContext.SessionState.InvokeCommand.GetCommand($commandName,'Function').ScriptBlock.Attributes) {
    if ($attributes -is [ArgumentCompleter]) {
        # and registering it for each command name and alias.
        foreach ($commandToComplete in $CommandNameAndAliases) {
            Register-ArgumentCompleter -CommandName $commandToComplete -ScriptBlock $attributes.ScriptBlock
        }        
        break
    }
}
