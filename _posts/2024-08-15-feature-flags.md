---
title: Adding "feature flags" to a pipeline
tags:
 - devops
 - yaml
 - pipeline
excerpt: Using "extends" template and "feature flags" in an Azure DevOps pipeline
cover: /assets/images/leaf7.webp
comments: true
layout: article
key: 20240821
mermaid: false
published: true
---
{% assign sBrace = '${{' %}
{% assign eBrace = '}}' %}

![image]({{ page.cover }}){: width="{{ site.imageWidth }}" }

This is the fourth in a series of posts about creating reusable Azure DevOps YAML pipelines across many projects. In these posts, I'll start with simple CI/CD pipelines and progress to a complex, dynamic pipeline.

1. [CI/CD YAML Pipelines](/2024/08/10/typical-pipeline.html)
1. [Creating a Build Pipeline Template](/2024/08/11/build-template-repository.html)
1. [Creating a Deploy Pipeline Template](/2024/08/21/deploy-template-repository.html)
1. Adding "feature flags" to a pipeline (this post)
1. [Dynamic CI/CD Pipeline](/2024/08/21/build-pipeline.html)
1. [Azure DevOps Pipeline Tips and Tricks](/2024/08/22/azdo-tat.html)

## The Problem

I have some nice templates to encapsulate my build and deploy pipelines. I have some new features to add to the pipelines, but I don't want to break the existing pipelines.

## The Solution

In this post, I'll add integration tests and image scanning to the build pipeline that will only run if a variable (feature flag) is set in the caller's variables YAML file. This allows me to have a high-level, standard build pipeline that many projects can use without having one-off pipelines for different situations. In my current position, this technique has allowed me to add several new features over time, keeping all the changes in the templates repo and avoiding custom YAML. I've also used this to take care of exception cases.

### Image Scanning

[Trivy](https://trivy.dev/) is a container image scanner that detects vulnerabilities in your code or Docker images. You can install it locally, or run it from a container. By adding it to the build pipeline, I can be more proactive about vulnerabilities in my images. (Instead of my boss sending me a Vanta report about vulnerabilities in my image.)

In the pipeline, I'll run it in a container to avoid customizing the build agent. Instead of adding the steps to the build pipeline, I'll create a template and call the template from the build pipeline. I'll run the Trivy scan, then use PowerShell to process the output and setting the result of the build based on the results.

```yaml
{% raw %}
# steps/scan-image.yml scan a local image for vulnerabilities using Trivy
parameters:
  - name: dockerImage
    displayName: Image name to scan, including registry
    type: string

  - name: failIfHigh
    displayName: Fail the build if high vulnerabilities are found (true/false)
    type: string

  - name: lowestSeverity
    displayName: Minimum severity level to report (LOW, MEDIUM, HIGH)
    type: string
    default: 'MEDIUM'
    values:
      - 'LOW'
      - 'MEDIUM'
      - 'HIGH'
steps:

  - task: Docker@2
    displayName: 'Scan image for vulnerabilities'
    inputs:
      command: 'run'
      arguments: >-
        --rm -v /var/run/docker.sock:/var/run/docker.sock
        -v $(Agent.TempDirectory):/tmp
        aquasec/trivy
        image ${{ parameters.registryName }}/${{ parameters.dockerImage }} -f json -o /tmp/output.json -q --scanners vuln --ignore-unfixed
      addPipelineData: false
      addBaseImageData: false

  - pwsh: |
      $output = Join-Path $env:outputFolder "output.json"
      if (!(Test-Path $output)) {
        Write-Error "Trivy output file not found. Check the previous step for errors."
        exit 1
      }

      $result = Get-Content $output | ConvertFrom-Json -depth 20
      $vulns = $result.Results | Select-Object Vulnerabilities
      $groups = $vulns.Vulnerabilities | Select-Object Severity, VulnerabilityID, PkgName, Status, InstalledVersion, FixedVersion, PrimaryURL | Group-Object severity

      $report = @()
      # grab the results they want by severity
      $g = $groups | Where-Object name -in 'HIGH','CRITICAL'
      if ($g) {
        $report += $g.group
      }
      $hasHigh = [bool]$report
      if ($env:highestSeverity -ne 'HIGH') {
        $g = $groups | Where-Object name -eq 'MEDIUM'
        if ($g) {
          $report += $g.group
        }
      }
      if ($env:highestSeverity -eq 'LOW') {
        $g = $groups | Where-Object name -eq 'LOW'
        if ($g) {
          $report += $g.group
        }
      }

      # output the results
      if ($report -and $report.Count -gt 0) {
        $report | Format-Table -AutoSize | Out-String -Width 1000

        # set the build result
        if ($hasHigh -and $env:failIfHigh -eq 'true') {
            Write-Host "##vso[task.logissue type=error]High vulnerabilities found in image $env:image"
            Write-Host "##vso[task.complete result=Failed;]"
        } else {
            Write-Host "##vso[task.logissue type=warning]Fixable vulnerabilities found in image $env:image"
            Write-Host "##vso[task.complete result=SucceededWithIssues;]"
        }
      } else {
        Write-Host "No fixable vulnerabilities found in image $env:image"
        Write-Host "##vso[task.complete result=Succeeded;]"
      }

    displayName: 'Process scan output'
    env:
      image: ${{ parameters.dockerImage }}
      failIfHigh: ${{ parameters.failIfHigh }}
      outputFolder: $(Agent.TempDirectory)
      highestSeverity: ${{ parameters.lowestSeverity }}
{% endraw %}
```

The Docker command runs Trivy against the locally built image and writes the results to a JSON file in the agent's temp directory. The `--ignore-unfixed` parameter tells Trivy not to report on vulnerabilities that do not have fixes, since I don't want to annoy developers with non-actionable warnings. The PowerShell script processes the JSON to create a concise report. It will also set the step's result to warning, and if there are HIGH or CRITICAL and the `failIfHigh` parameter is set to true, it will fail the step and the pipeline. It sets these results via the [logging commands](https://learn.microsoft.com/en-us/azure/devops/pipelines/scripts/logging-commands?view=azure-devops&tabs=bash) `task.logIssue` and `task.complete`.

I could add these steps to the end of the `steps/build.yml` template file, but instead, I'll create a job template that will call two templates.

```yaml
{% raw %}
# jobs/build.yml
parameters:
    # 👇 This will also have all the parameters from steps/build.yml, omitted for clarity

  - name: devOpsFolder
    type: string
    default: ./DevOps

jobs:
  - job: build
    displayName: Build
    pool:
      vmImage: ubuntu-latest

    variables:
      # 👇 First load default values from the template repo, then any overrides
      - template: variables/defaults.yml
      - template: ${{ parameters.devOpsFolder }}/variables/common.yml@self

    steps:
      - template: ../steps/build.yml        # 👈 Call the build steps template
        parameters:
          isDryRun: ${{ parameters.isDryRun }}
          repositoryName: ${{ parameters.repositoryName }}
          tags: ${{ parameters.tags }}
          dockerfile: ${{ parameters.dockerfile }}
          context: ${{ parameters.context }}
          buildNumber: ${{ parameters.buildNumber }}

      # 👇 Add the image scanning step if they opted into it.
      - ${{ if eq(variables.scanImage,'true') }}:
        - template: ../steps/scan-image.yml
          parameters:
            dockerImage: ${{ parameters.repositoryName }}:${{ split(parameters.tags, ',')[0] }}
            failIfHigh: ${{ variables.trivy-failIfHigh }}
            lowestSeverity: ${{ variables.trivy-lowestSeverity }}
{% endraw %}
```

The way the feature flags works is the two variables template files above. The `variables/defaults.yml` file is in the templates repo and contains the default values for the variables. That way we always will have a value for them, and they will have appropriate defaults. In the earlier post about deploy templates, I used `@self` to load a template from the caller's repo. I use it again here to load any overrides for the `variables/default.yml`. If the caller doesn't have a `variables/common.yml` file, the pipeline will fail to start. When creating your template repo, requiring a common and environment-specific variables file from the get-go will make future changes easier. Here's part of the `variables/defaults.yml` file:

```yaml
# variables/defaults.yml
# default values for variables that the caller can override in their common.yml file
variables:

  # set to true to run the trivy scan
  - name: trivyScan
    value: 'false'
```

In the example's `DevOps-feature-flags/build.yml` instead of including `steps/build.yml`, it now includes `jobs/build.yml`

```yaml
{% raw %}
jobs:
  - template: jobs/build.yml@templates
    parameters:
      repositoryName: sample-api
      isDryRun: ${{ parameters.isDryRun }}
      tags: $(tags)
      devOpsFolder: 'DevOps-feature-flags'
{% endraw %}
```

To opt into the image scanning for the example, I added `variables/common.yml` and turned on Trivy as shown below. I like to provide a sample `common.yml` with all possible values they can use, with the values commented out, similar to many Linux configuration files.

```yaml
# overrides of template variables
variables:

  # set to true to run the trivy scan. Default is false
  - name: trivyScan
    value: 'true'

  # set to true to fail the build if any HIGH or CRITICAL severity vulnerabilities are found. Default is false
  # - name: trivyFailIfHigh
  #   value: 'true'

  # set to lowest level severity to report on, default is MEDIUM. Valid values are LOW, MEDIUM, HIGH
  # - name: trivyLowestSeverity
  #   value: 'HIGH'
```

Since I used the template syntax to conditionally include the steps, `{{sBrace}}if{{eBrace}}`, they will not even show up in the pipeline if you haven't opted in. Here are two runs, one with the scan and one without. (In the next post I'll skip steps instead of excluding them.)

![Including steps](/assets/images/devOpsBlogs/scan-steps.png)

Hopefully, when you run the scan, you'll get a green build, and output will be similar to this:

```plaintext
No fixable vulnerabilities found in image sample-api:1154-prerelease

Finishing: Process scan output
```

If you have vulnerabilities, the step, job, and stage will be marked with a warning.

![Warning step](/assets/images/devOpsBlogs/scan-warning.png)

The output will be similar to this:

```plaintext
Severity VulnerabilityID PkgName                   Status       InstalledVersion        FixedVersion   PrimaryURL
-------- --------------- -------                   ------       ----------------        ------------   ----------
MEDIUM   CVE-2024-29992  Azure.Identity            fixed        1.10.4                  1.11.0         https://avd.aquasec.com/nvd/cve-2024-29992
MEDIUM   CVE-2024-35255  Azure.Identity            fixed        1.10.4                  1.11.4         https://avd.aquasec.com/nvd/cve-2024-35255
MEDIUM   CVE-2024-35255  Microsoft.Identity.Client fixed        4.56.0                  4.60.4, 4.61.3 https://avd.aquasec.com/nvd/cve-2024-35255


##[warning]Fixable vulnerabilities found in image sample-app:dev-138545
```

## Summary

In this post, I showed you how to add a feature to a template that can be opted into by setting a variable in the caller's file. This technique does require some planning of your templates, but once in place you can easily add new features, or behavior to a pipeline without changing the caller's pipeline.

In the next post, I'll show how to create a dynamic pipeline that determines what stages and jobs run based on variables at runtime.

## Links

- [This sample's source](https://dev.azure.com/MrSeekatar/SeekatarBlog/_git/TypicalPipeline) The DevOps files are in the DevOps-feature-flags folder.
- [This sample's Build pipeline in Azure DevOps](https://dev.azure.com/MrSeekatar/SeekatarBlog/_build?definitionId=53)
- [The template repo](https://dev.azure.com/MrSeekatar/SeekatarBlog/_git/azdo-templates)
- [Trivy](https://trivy.dev/) vulnerability scanner

Azure DevOps documentation:

- [Logging commands](https://learn.microsoft.com/en-us/azure/devops/pipelines/scripts/logging-commands?view=azure-devops&tabs=bash)
- [task.logIssue](https://learn.microsoft.com/en-us/azure/devops/pipelines/scripts/logging-commands?view=azure-devops&tabs=bash#logissue-log-an-error-or-warning) to set a step's result
- [task.complete](https://learn.microsoft.com/en-us/azure/devops/pipelines/scripts/logging-commands?view=azure-devops&tabs=bash#complete-finish-timeline) to set a pipeline's result
