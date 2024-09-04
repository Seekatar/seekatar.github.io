---
title: Creating a Deploy Pipeline Template
tags:
 - devops
 - yaml
 - deploy
 - pipeline
 - template
 - azure-devops
excerpt: Moving Azure DevOps deploy pipeline logic to a template repository
cover: /assets/images/leaf6.webp
comments: true
layout: article
key: 20240811
---

![image]({{ page.cover }}){: width="{{ site.imageWidth }}" }

This is the third in a series of posts about creating reusable Azure DevOps YAML pipelines across many projects. In these posts, I'll start with simple CI/CD pipelines and progress to a complex, dynamic pipeline.

1. [CI/CD YAML Pipelines](/2024/08/10/typical-pipeline.html)
1. [Creating a Build Pipeline Template](/2024/08/11/build-template-repository.html)
1. Creating a Deploy Pipeline Template (this post)
1. [Adding "feature flags" to a pipeline](/2024/08/15/feature-flags.html)
1. Dynamic CI/CD Pipeline (coming soon)
1. [Azure DevOps Pipeline Tips and Tricks](/2024/08/22/azdo-tat.html)

> 💁 I assume you have read the previous blogs and are familiar with the basic application lifecycle concepts for containerized applications.

The YAML, sample source code, and pipelines are all in [this](https://dev.azure.com/MrSeekatar/SeekatarBlog/_git/TypicalPipeline) AzDO Project.

## The Problem

Now that I have a nice set of YAML CI/CD pipelines, I want to reuse them across my organization. Many of my applications are similar, and they all deploy using Helm.

## The Solution

In this post, I'll take the deploy yaml from a previous post, and move chunks of YAML (templates) into a separate repository. Then I can use those chunks in pipelines across my organization. By having one central location, I can make changes and fixes to the shared YAML and have all the pipelines that use it updated.

### Creating the Deploy Templates

The deploy pipeline for the example is mainly stubbed out since deployment will be unique to your situation. Although unique to your situation, it will probably be the same for many of your applications. In this example, I'll show how you can create a template that will deploy to Kubernetes using Helm. The steps to do so are as follows:

1. For each environment
    1. Get the K8s credentials
    1. Log into K8s
    1. Replace environment-specific values in the Helm values.yaml file
    1. Call a script to use K8sUtils to deploy to Helm

Recall that the deploy pipeline uses ${{sBrace}}each{{eBrace}} to create a `stage` for each environment. Each `stage` then has a `job` to run the deployment. For maximum flexibility, I'll create three templates. I'll start from the bottom, `steps` and work my way up to `stages`.

Let's look at the `stages from the deploy YAML:

```yaml
{% raw %}
stages:
- ${{ each env in parameters.environments }}: # 👈 stages template will need environments
  - stage: deploy_${{ lower(env) }}
    displayName: Deploy ${{ env }}

    variables:
      - name: appName
        value: sample-api                     # 👈 Hard-coded name
      - name: envLower
        value: ${{ lower(env) }}
      - name: imageTag                        # 👈 Bending the global variable rule a bit
        value: $(resources.pipeline.build_pipeline.runID)

      # 👇 We'll have to deal this this
      - template: variables/${{ variables.envLower }}-environment.yml

    jobs:
    - job: deploy_${{ variables.envLower }}   # 👈 jobs template will this parameter
      displayName: Deploy ${{ env }}          # 👈 and this
      pool:
        vmImage: ubuntu-latest

      steps:
      # - task: AzureKeyVault@2 # A task to get secrets for the K8s login step below

      # - task: Kubernetes@1    # To deploy with Helm, we need to connect to the cluster

      - task: qetza.replacetokens.replacetokens-task.replacetokens@5
        displayName: 'Replacing #{VAR}#. Will error on missing variables'
        inputs:
          # 👇 I'll let them override where this file is to avoid hard-coding it
          targetFiles: ./DevOps/values.yaml => $(Agent.TempDirectory)/values.yaml
          actionOnMissing: fail

      - pwsh: |
          Get-Content $(Agent.TempDirectory)/values.yaml
        displayName: 'Show Helm Values'

      - pwsh: |
          if ($env:isDryRun -eq 'true') {
            Write-Host "This is a dry run. No deployment will be done."
          } else {
            Write-Host "Deploying to $env:env"
          }
          Write-Host "This is a fake deployment step."
          Write-Host "Replace this with steps to deploy your own app wherever you want."
          Write-Host "Using K8sUtils and helm is a great way to deploy to Kubernetes"
        displayName: Deploy $(appName)        # 👈 using appName variable
        env:
          isDryRun: $(isDryRun)
          environment: $(env)                 # 👈 The env needs to get down to the steps
{% endraw %}
```

Since much of the deploy is stubbed out, there's not much to replace. Some of the hard-coded values are now parameters. Note that the `replacetokens` task uses current environment variables, like `imageTag` for substitution. I could pass that in as a parameter instead, but then I'd have to add a step to set it as a variable, too, so bend the global variable rule a bit. In the next post, I'll show a better (different) solution. Here is the `steps` template:

```yaml
{% raw %}
# steps/deploy.yml
parameters:
  - name: appName
    type: string

  - name: environment
    type: string

  - name: isDryRun
    type: boolean

  - name: valuesFilename
    type: string
    default: ./DevOps/values.yaml

steps:
  # - task: AzureKeyVault@2 # A task to get secrets for the K8s login step below

  # - task: Kubernetes@1    # To deploy with Helm, we need to connect to the cluster

  - task: qetza.replacetokens.replacetokens-task.replacetokens@5
    displayName: 'Replacing #{VAR}#. Will error on missing variables'
    inputs:
      # ✅
      targetFiles: ${{ parameters.valuesFileName }} => $(Agent.TempDirectory)/values.yaml
      actionOnMissing: fail

  - pwsh: |
      Get-Content $(Agent.TempDirectory)/values.yaml
    displayName: 'Show Helm Values'

  - pwsh: |
      if ($env:isDryRun -eq 'true') {
        Write-Host "This is a dry run. No deployment will be done."
      } else {
        Write-Host "Deploying to $env:environment"
      }
      Write-Host "This is a fake deployment step."
      Write-Host "Replace this with steps to deploy your own app wherever you want."
      Write-Host "Using K8sUtils and helm is a great way to deploy to Kubernetes"
    displayName: Deploy ${{ parameters.appName }}                # ✅
    env:
      isDryRun: $(isDryRun)
      environment: ${{ parameters.environment }}                 # ✅
{% endraw %}
```

The `jobs` template is just sets up the environment, then invokes the `steps/deploy.yml` template. Notice that the `template` path is different since we're in a template in the template repository. To reference a template within the same repository you use a path relative to the current file, and do not append the resource name (e.g. `@templates`).

```yaml
{% raw %}
# jobs/deploy.yml
parameters:
  - name: appName
    type: string

  - name: environment
    type: string

  - name: isDryRun
    type: boolean

  - name: valuesFilename
    type: string
    default: ./DevOps/values.yaml


jobs:
  - job: deploy_${{ lower(parameters.environment }}
    displayName: Deploy ${{ parameters.environment }}
    pool:
      vmImage: ubuntu-latest

    steps:
      - template: ../steps/deploy.yml     # 👈 relative path, no @templates
        parameters:
          appName: ${{ parameters.appName }}
          environment: ${{ parameters.environment }}
          isDryRun: ${{ parameters.isDryRun }}
          valuesFilename: ${{ parameters.valuesFilename }}
{% endraw %}
```

The `stages` template has the `environments` parameter. It loops over them to create a `stage` that calls the `jobs/deploy.yml` template. It also creates the `imageTag` variable, which will be used as a replacement in the `values.yaml` file later on. I'll discuss the variable template below.

```yaml
{% raw %}
# stages/deploy.yml
parameters:
  - name: appName
    type: string

  - name: environments
    type: object
    displayName: Environments to deploy to
    default:
      - red
      - green
      - blue
    values:
      - red
      - green
      - blue

  - name: isDryRun
    type: boolean

  - name: devOpsFolder
    type: string
    default: ./DevOps

  - name: valuesFilename
    type: string
    default: ./DevOps/values.yaml

stages:
  - ${{ each env in parameters.environments }}:
    - stage: deploy_${{ lower(env) }}
      displayName: Deploy ${{ env }}

      variables:
        - name: imageTag  # substituted in values.yaml
          value: $(resources.pipeline.build_pipeline.runID)

        - template: ${{ parameters.devOpsFolder }}/variables/${{ lower(env) }}-environment.yml@self

      jobs:
        - template: ../jobs/deploy.yml
          parameters:
            appName: ${{ parameters.appName }}
            environment: ${{ env }}
            isDryRun: ${{ parameters.isDryRun }}
            valuesFilename: ${{ parameters.valuesFilename }}
{% endraw %}
```

In the original deploy pipeline, we used a template to pull in variables in our repo. To be able to do the same thing in the template I use the `@self` suffix, which tells AzDO that instead of loading the template from this repository, load it from the caller's repository. Of course, the caller *must* have a file that matches that path, or the pipeline will fail to start. This is where breaking up the templates could be useful. If an app wanted to get variables differently, it could and still use the job template.

### Calling the Deploy Template

Now that we have a template, let's revamp the old build pipeline to use it.

```yaml
{% raw %}
name: '1.1.$(Rev:r)-$(DeploySuffix)'

parameters:
- name: environments
  type: object
  displayName: Environments to deploy to
  default:
    - red
    - green
    - blue
  values:
    - red
    - green
    - blue

- name: isDryRun
  displayName: Do a Dry Run
  type: boolean
  default: false

trigger: none
pr: none

variables:
  - name: deploySuffix
    # Set the build suffix to DRY RUN if it's a dry run, that is used in the name
    ${{ if parameters.isDryRun }}:
      value: '-DRYRUN'
    ${{ else }}:
      value: ''

resources:
  pipelines:
  - pipeline: build_pipeline  # a name for accessing the build pipeline, such as runID below
    # 👇 different for the templated deploy to trigger off templated build
    source: build_templated_sample-api  # MUST match the AzDO build pipeline name
    trigger:
      branches:
        include:
          - main              # Only trigger a deploy from the main branch build
  repositories:
    - repository: templates         # name after the @ below
      type: git
      name: azdo-templates
      ref: releases/v1.0

stages:
# 👇 ripped out all the stages and added the template
- template: stages/deploy.yml@templates
  parameters:
    appName: sample-api
    environments: ${{ parameters.environments }}
    isDryRun: ${{ parameters.isDryRun }}
    # 👇 these are optional, and the defaults work for this app
    # devOpsFolder: ./DevOps
    # valuesFilename: ./DevOps/values.yaml
{% endraw %}
```

This deploy pipeline will be triggered by the `build_templated_sample-api` pipeline and run the same steps as before, only now they are in a reusable template. Here's a screenshot of the original pipeline on the left and the templated pipeline on the right. Both have the same stages,  jobs, and steps.

![Comparing two deploy runs](/assets/images/devOpsBlogs/compare-deploys.png)

## Summary

In this post, I showed you have to take a deploy pipeline and create a template from it. Converting any YAML pipeline will follow the same steps. In the next post, I'll create a data-driven pipeline giving users great flexibility, and reusability.

## Links

- [This sample's source](https://dev.azure.com/MrSeekatar/SeekatarBlog/_git/TypicalPipeline) the YAML is in the `DevOps-templated` folder
- [This sample's Deploy pipeline in Azure DevOps](https://dev.azure.com/MrSeekatar/SeekatarBlog/_build?definitionId=52)

Azure DevOps documentation:

- [Templates](https://learn.microsoft.com/en-us/azure/devops/pipelines/process/templates?view=azure-devops&pivots=templates-includes)
- [Template Parameters](https://learn.microsoft.com/en-us/azure/devops/pipelines/process/template-parameters?view=azure-devops)
