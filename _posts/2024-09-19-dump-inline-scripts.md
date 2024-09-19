---
title: Azure DevOps Inline Script Tips
tags:
 - devops
 - yaml
 - pipeline
 - build
 - deploy
excerpt: Helpful tips for running inline scripts in Azure DevOps pipelines
cover: /assets/images/leaf8.png
comments: true
layout: article
key: 20240919
---

![image]({{ page.cover }}){: width="{{ site.imageWidth }}" }

Before you even commit an inline script, paste it an editor with syntax highlighting. An errant or missing quote or parenthesis will be much easier to spot.

![alt text](/assets//images/pwsh-syntax-error.png)

I try to avoid using macro or template syntax in an inline script (`$(macroSyntax)` `${{ templateSyntax }}`). Since it is a verbatim replacement, things can get messy if the variable or parameter contains a `$` or `"`. Instead use the `env:` block to set environment variables that can be used in the script. That also makes it easier to test the script locally.

```yaml
- pwsh: |
    Write-Host "MyVar is $env:MyVar"
    Write-Host "MyParam is $env:MyParam"
    env:
      MyVar: $(MyVar)
      MyParam: ${{ parameters.MyParam }}
```

To test the inline script, paste it into a file, add the environment variables, and run it locally. As usual, watch indenting.

```powershell
$env:MyVar = "TestingVar"
$env:MyParam = "TestingParam"

# --------- inline script ---------
    Write-Host "MyVar is $env:MyVar"
    Write-Host "MyParam is $env:MyParam"
```

Sometimes you'll get an error in an inline script that is baffling. If you really get stuck you can dump out the generated scripts by adding a step like this:

```yaml
 - pwsh: |
      Get-Item $(Agent.TempDirectory)/*.ps1 | ForEach-Object {
       ">>>>>>>>>>>>>>>>>>> $($_.FullName)"
       Get-Content $_.FullName
       "`n"
       }
    displayName: 'Dump Generated ps1 files'
    condition: always()
```

When you run an inline script, it will log the name of the script, which you can then look for in the logs.

```plaintext
==============================================================================
Task         : PowerShell
Description  : Run a PowerShell script on Linux, macOS, or Windows
Version      : 2.245.1
Author       : Microsoft Corporation
Help         : https://docs.microsoft.com/azure/devops/pipelines/tasks/utility/powershell
==============================================================================
Generating script.
========================== Starting Command Output ===========================
/usr/bin/pwsh -NoLogo -NoProfile -NonInteractive -Command . '/agent/_work/_temp/d6826bfb-2151-4e5b-aa40-a1dd2c24d1cc.ps1'
```

Hope that helps!
