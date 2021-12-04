---
author: seekatar
title: Testing a Helm Chart
tags:
 - helm
 - powershell
 - testing
 - code
synopsis: Locally testing Helm chart changes
cover: /assets/images/grape-vine-leaf-1327453-1279x851.jpg
comments: true
---

![image](/assets/images/grape-vine-leaf-1327453-1279x851.jpg){: width="{{ site.imageWidth }}" }

## Problem

I have to make a change to a Helm chart and I want to make sure it generates the correct manifests, and it didn't break anything.

## Solution

As my wont, I have a `run.ps1` script in the root of the repo that runs all the little snippets of command line that I need for a project. For the helm chart project, that script will run pack, install, lint, dry-run, etc. One thing it didn't do was verify that the chart produces the desired output. I did have sample `*-values.yaml` files, but I would just pass them to dry-run and see if they looked correct.

To test them, I took a page from Jest Vue web UI testing that uses a snapshot which is later used for comparison. My plan was as follows:

1. Create a `tests` folder with all the sample values files
1. Do a `--dry-run` on each, saving the output for the base line
1. Add a `test` task to `run.ps1` that will run a `--dry-run` on all the samples, and verify that they match the baseline.

This was pretty straight forward. When doing the compare, I found that the `app.kubernetes.io/instance` and `LAST DEPLOYED` are different on each run, so the script must do a bit of editing before comparing. Here's the code that does that.

```PowerShell
helm install . --dry-run --generate-name --values $valuesFile | ForEach-Object {
    ($_ -replace "chart-\d+","chart-0000000000") -replace "LAST DEPLOYED: .*","LAST DEPLOYED: NEVER"
} | Out-File $outputFile -Append

```

Since I want to be as flexible as possible, including cross-platform, the code that does the compare has to be configurable. To that end, you can pass in a scriptblock that takes two files and returns `$true` if they match. Since I'm on Windows, I have it default to `fc.exe` in the param block like this:

```PowerShell
[scriptblock] $FileCompare = { param($left, $right) fc.exe $left $right > $null; return $LASTEXITCODE -eq 0 },
```

Here's a successful run

```PowerShell
C:\code\helm\helm-micro-service [main ≡ +0 ~1 -0 !]> .\run.ps1 test

OK C:\code\helm\helm-micro-service\tests\batch-processor-values.yaml
OK C:\code\helm\helm-micro-service\tests\batch-processor-volume-json-values.yaml
OK C:\code\helm\helm-micro-service\tests\batch-processor-volume-string-values.yaml
W1022 20:34:38.601136   12628 warnings.go:70] networking.k8s.io/v1beta1 Ingress is deprecated in v1.19+, unavailable in v1.22+; use networking.k8s.io/v1 Ingress
W1022 20:34:38.604549   12628 warnings.go:70] networking.k8s.io/v1beta1 Ingress is deprecated in v1.19+, unavailable in v1.22+; use networking.k8s.io/v1 Ingress
OK C:\code\helm\helm-micro-service\tests\first-party-ui-values.yaml
```

Of course when you update the chart it will not match the baseline, but now that I actually have a baseline, I can compare the new manifests with the baseline to see if the changes are what I want. When running `test`, if the files are different, it will show the names so you can compare them.

```PowerShell
WARNING: Diff between ..\tests\output\batch-processor-values.yaml and C:\Users\User\AppData\Local\Temp\batch-processor-values.yaml
```

And of course once your changed the chart, the baseline is stale. To update the baseline, you simply run the `test` and pas in the baseline folder as the `-TempFolder` parameter (which defaults to `$env:TMP`)

```PowerShell
.\run.ps1 test -TempFolder tests\output
```

## Summary

Automated testing always gives you a modicum of confidence that you haven't broken anything to obvious. With Helm, testing changes locally can be tricky since a local environment won't ever really match your CI/CD, but this should help.

All of this is in the [helm-micro-service](https://github.com/Seekatar/helm-micro-service) repo.
