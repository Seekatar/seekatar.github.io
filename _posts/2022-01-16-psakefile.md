---
author: seekatar
title: Psake Task Name Completion
tags:
 - powershell
 - psake
 - argumentCompleter
 - code
excerpt: Using an argument completer for a psake wrapper
cover: /assets/images/black-magic-leaves-1191640.jpg
comments: true
layout: article
key: foreach-git
---

![image](/assets/images/black-magic-leaves-1191640.jpg){: width="{{ site.imageWidth }}" }

## Problem

[psake](https://psake.readthedocs.io/en/latest/) is a build automation tool for PowerShell that I use in almost every repo I create to wrap all those commands I want to use for the repo, which can be quite a few. For example one project had these:

* Build
* BuildMessage
* ci
* DockerBuild
* DockerInteractive
* DockerRun
* DockerStop
* DumpVars
* GetReady
* HelmDependencyBuild
* HelmInstall
* HelmUninstall
* IntegrationTest
* OpenSln
* StartBack
* StartBackInteractive
* StopBack
* TestClient
* UnitTest

Instead of calling psake directly, I have a `run.ps1` that makes a better user experience since it has project-specific parameters with validation, help, pre-req checks, etc. I used to use a `ValidateSet` on the `tasks`, but that had to be updated every time the task list was touched. The problem is how can that be automatic?

## Solution

An argument completer scriptblock can get all the tasks names dynamically so I never have to worry about having a stale `ValidateSet` any more.

> The official doc for argument completers is here:
>
> * [Register-ArgumentCompleter](https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.core/register-argumentcompleter?view=powershell-7.2)
> * [ArgumentCompleter Attribute](https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_functions_argument_completion?view=powershell-7.2#argumentcompleter-attribute)

### Using Register-ArgumentCompleter

There are two ways to do this. First is to use [Register-ArgumentCompleter](https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.core/register-argumentcompleter?view=powershell-7.2) to register a global completer for all `run.ps1` scripts. The following snippet registers a scriptblock for the `task` parameter of `run.ps1`. You can add this to your `$Profile` file.

```powershell
Register-ArgumentCompleter -CommandName run.ps1 -ParameterName task -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
        $psakeFile = (Join-Path (Split-Path $commandAst -Parent) psakeFile.ps1)
        if (Test-Path $psakeFile) {
            Get-Content $psakeFile |
            Where-Object { $_ -match "^task ([\w+-]+)" } |
            ForEach-Object {
                if ( !($fakeBoundParameters[$parameterName]) -or
                    (($matches[1] -notin $fakeBoundParameters.$parameterName) -and
                        ($matches[1] -like "*$wordToComplete*"))
                ) {
                    $matches[1]
                }
            }
        }
    }
```

The scriptblock is called when the user presses tab when entering the `task` parameter. It finds the `psakefile.ps1` in `run.ps1`'s folder, then parses out the task names with a specific regex (yours may vary). If the user hasn't typed anything aside from tab, each task name is returned. If the user typed some letters (`$wordToComplete`), it returns task names that contain that text. I match on anywhere in the task name, but you may match only on tasks that start with the typed letters by removing the leading asterisk from the `-like`: `($matches[1] -like "$wordToComplete*"))`

This method registered the scriptblock for _all_ `run.ps1` scripts so if that doesn't work for you, you can use the second method.

### Using ArgumentCompleter Attribute

Inside `run.ps1` itself you can use the same scriptblock from the first method in an [ArgumentCompleter Attribute](https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_functions_argument_completion?view=powershell-7.2#argumentcompleter-attribute). In this case it applies to only the `Task` parameter for this `run.ps1`.

> Note Register-ArgumentCompleter will override the ArgumentCompleter Attribute.

```powershell
[CmdletBinding()]
param(
    [ArgumentCompleter({
        param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
        $psakeFile = (Join-Path (Split-Path $commandAst -Parent) psakeFile.ps1)
        if (Test-Path $psakefile) {
            Get-Content $psakefile |
                    Where-Object { $_ -match "^task ([\w+-]+)" } |
                    ForEach-Object {
                        if ( !($fakeBoundParameters[$parameterName]) -or
                            (($matches[1] -notin $fakeBoundParameters.$parameterName) -and
                             ($matches[1] -like "*$wordToComplete*"))
                            )
                        {
                            $matches[1]
                        }
                    }
        }
     })]
    [string[]] $Task = 'Default'
)
```

### Debugging an Argument Completer

If you don't get your expected tab completion, you usually have an error in the script block. Completers are mainly pretty small, but you can pack a lot of bugs in there. If you can isolate code and test it outside the completer, that is useful. `$Error`, and in particular `$Error[0]`, will show the recent errors, but if it's a logic bug there won't be an error.

The output from the scriptblock is used by the caller for the tab-completion, so `Write-Output` is not what you want. You can use `Write-Host`, `Write-Information`, and `Write-Warning`, but it does muddy your prompt as you tab around. I usually use `Out-File -Append` to a log file and then use `Get-Content -Wait` on that file in another window.

I haven't had any luck with VSCode debugging. It will break, but then hangs.
