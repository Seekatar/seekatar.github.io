#!/usr/bin/pwsh
param (
    [ArgumentCompleter({
        param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
        $runFile = (Join-Path (Split-Path $commandAst -Parent) run.ps1)
        if (Test-Path $runFile) {
            Get-Content $runFile |
                    Where-Object { $_ -match "^\s+'([\w+-]+)' {" } |
                    ForEach-Object {
                        if ( !($fakeBoundParameters[$parameterName]) -or
                            (($matches[1] -notin $fakeBoundParameters.$parameterName) -and
                             ($matches[1] -like "$wordToComplete*"))
                            )
                        {
                            $matches[1]
                        }
                    }
        }
     })]
    [string[]] $Tasks,
    [string] $Version # common extra parameter
)

$currentTask = ""

# execute a script, checking lastexit code
function executeSB
{
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [scriptblock] $ScriptBlock,
    [string] $WorkingDirectory = $PSScriptRoot,
    [string] $TaskName = $currentTask
)
    if ($WorkingDirectory) {
        Push-Location $WorkingDirectory
    }
    try {
        $global:LASTEXITCODE = 0
        Invoke-Command -ScriptBlock $ScriptBlock

        if ($LASTEXITCODE -ne 0) {
            throw "Error executing command '$TaskName', last exit $LASTEXITCODE"
        }
    } finally {
        if ($WorkingDirectory) {
            Pop-Location
        }
    }
}
if (!$Tasks) {
    Write-Warning "No tasks specified"
    return
}

foreach ($currentTask in $Tasks) {

    try {
        $prevPref = $ErrorActionPreference
        $ErrorActionPreference = "Stop"

        "-------------------------------"
        "Starting $currentTask"
        "-------------------------------"

        switch ($currentTask) {
            'serve' {
                executeSB -WorkingDirectory (Join-Path $PSScriptRoot .) {
                  try {
                  if ($IsMacOS) {
                    Write-Information "MacOS detected, using Gemfile.lock.mac" -InformationAction Continue
                    Copy-Item -Path Gemfile.lock Gemfile.lock.bak -Force
                    Copy-Item -Path Gemfile.lock.mac Gemfile.lock -Force
                  }
                  bundle exec jekyll serve --livereload
                  } finally {
                    if ($IsMacOS) {
                      Write-Information "MacOS detected, restoring Gemfile.lock" -InformationAction Continue
                      Copy-Item -Path Gemfile.lock.bak Gemfile.lock -Force
                    }
                  }
                }
            }
            default {
                throw "Invalid task name $currentTask"
            }
        }

    } finally {
        $ErrorActionPreference = $prevPref
    }
}
