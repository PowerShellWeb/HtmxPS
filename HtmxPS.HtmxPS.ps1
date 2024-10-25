#requires -Module HtmxPS
Start-Htmx -Htmx @(
    "<div style='text-align:center'>"
    "<svg width='50%' height='50%'>"
    Get-Content (Join-Path $PSScriptRoot -ChildPath 'Assets' | Join-Path -ChildPath "HtmxPS-Animated.svg") -Raw
    "</svg>"
    "</div>"

    htmx button "Random Number" hx-target "#stage" hx-get "/Get-Random"
    htmx div -id stage
) -Route @{
    "/Get-Random" = { Get-Random }
} -PaletteName kanagawabones
