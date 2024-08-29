---
title: Using a Template Repository for Azure DevOps Build Pipeline
tags:
 - devops
 - yaml
 - pipeline
 - featureflags
excerpt: Moving pipeline logic to a template repository, with feature flags
cover: /assets/images/leaf2.png
comments: true
layout: article
key: 20240811
---

![image]({{ page.cover }}){: width="{{ site.imageWidth }}" }

This is the second in a series of blog posts about creating reusable Azure DevOps YAML pipelines across many projects. In these posts, I'll build a containerized .NET API with unit tests and do deployments to multiple environments (faked-out). This first post creates pipelines as one-offs without reusing YAML. The second and third posts will leverage templates to create a reusable library of pipeline steps. The fourth post will take templates to the next level by creating a dynamic pipeline driven by feature flags.

1. [Typical Kubernetes Build and Deploy Azure DevOps Pipelines](/2024/08/10/typical-pipeline.html)
1. Moving Azure DevOps Build Pipeline Logic to a Template Repository (this post)
1. Moving Azure DevOps Deploy Pipeline Logic to a Template Repository (coming soon)
1. [Creating a Dynamic Azure DevOps Pipeline](/2024/08/21/build-pipeline.html)
1. [Azure DevOps Pipeline Tips and Tricks](/2024/08/22/azdo-tat.html)

> 💁 I assume you have read the previous blog and are familiar with the basic application lifecycle concepts for containerized applications.

The YAML, sample source code, and pipelines are all in [this](https://dev.azure.com/MrSeekatar/SeekatarBlog/_git/TypicalPipeline) AzDO Project.

## The Problem

Now that I have a nice YAML CI/CD set of pipelines, I want to reuse then across my organization. Many of my applications are similar, and they all deploy to the same environment

## The Solution

In this post, I'll take the build YAML from the previous post, and move chunks of YAML (templates) into a separate repository. Then I can use those chunks in pipelines across my organization. By having one central location, I can make changes and fixes to the shared YAML and have all the pipelines that use it updated.

> 💁 Brief Lesson on Templates
>
> [Templates](https://learn.microsoft.com/en-us/azure/devops/pipelines/process/templates?view=azure-devops&pivots=templates-includes) are chunks of YAML that can be included in other YAML files, similar to `#include` in C++. In this post I'll use the term `template` to refer to `Includes Templates` (I'll cover `Extends Templates` in the next post).
>
> Each template contains one type of AzDO object, such as a `stages`, `jobs`, `steps`, or `variables`. One of those keywords will be in each file, and then it can only be used under the same keyword. E.g if the template has `steps` it can only go under `steps` in the calling YAML. Templates can have [parameters](https://learn.microsoft.com/en-us/azure/devops/pipelines/process/template-parameters?view=azure-devops), so you can make them as flexible as possible.
>

I used a template in the first post to pull in the variables for the pipeline. In that case the template was in the same repo as the caller. In this post the templates will be in a separate repo.

### The Template Repository

For the templates, I create an `azdo-templates` repository with the following structure:

```plaintext
.
├── jobs
├── stages
├── steps
└── variables
```

As the folder names suggest, each one will contain only templates of that type. To use templates from this repository, include the repository in the `resources` section of the calling pipeline, like the following:

```yaml
resources:
  repositories:
    - repository: templates         # Arbitrary name that we use to reference this repo
      type: git
      name: azdo-templates          # The name of the repo
      ref: releases/v1.0            # The branch to use
```

If I have a file `jobs/build.yml` in my repo, I can use it in a pipeline like this:

```yaml
jobs:
  - template: jobs/build.yml@templates # @templates is the 'repository' name from above
```

### Branching Strategy

Notice when I reference the `azdo-templates` repository, I use a branch name of `releases/v1.0`. The `main` branch of the template repo is always the latest branch, and will be in sync with the highest numbered `releases` branch. The process of making changes to the template is as follows:

1. Make a new branch off `main`
1. Make changes to the template
1. Test the changes in a calling pipeline by updating another pipeline to use the new branch
1. Merge the branch to `main`
1. If the changes are not breaking, merge `main` to the highest numbered `releases` branch, e.g. `releases/v1.0`
1. If the changes are breaking, branch off `main` with a new `releases` branch, e.g. `releases/v1.1`
1. Revert or update the ref in the calling pipeline.

This allows users of the template to get fixes or new functionality automatically. But if there are breaking changes, they can choose when to opt into the new release. (I initially used tags, but that got messy with git.)

### Creating the Build Templates

Looking at the build pipeline from the previous example it had the following tasks:

1. Checkout the code
1. Build and test in Docker
1. Publish the build output
1. Publish the test results
1. Publish the code coverage
1. If not a dry run
   1. Publish the Docker image locally
   1. Push the Docker image to the registry

That list of tasks should be what any Docker build runs. Let's see how to make that a `template`. We could make the template a stage, job, or steps. I'll make it steps since that way it can be used in any job. I can always wrap it in a job template if I need to.

The original pipeline had a dry run parameter, so we'll need that. Then since this template will go under `steps` in the calling pipeline, we'll add that to the template.

```yaml
parameters:
  - name: isDryRun
    type: boolean

steps:
```

I don't have a `default` or `displayName` for the parameter, since the name makes it obvious, and it will never be shown in the UI. I'll always want the caller to pass in the parameter, do it has no default.

In the build pipeline we set the tags variable like this:

```yaml
{% raw %}
variables:
  - name: tags
    ${{ if eq(variables['Build.SourceBranchName'],'main') }}:
      value: "$(Build.BuildId)"
    ${{ else }}:
      value: "$(Build.BuildId)-prerelease"
{% endraw %}
```

`steps` can't contain `variables` so we can't do the same thing. Instead we'll add another parameter.

```yaml
{% raw %}
  - name: tags
    type: string
    ${{ if eq(variables['Build.SourceBranchName'],'main') }}:
      default: "$(Build.BuildId)"
    ${{ else }}:
      default: "$(Build.BuildId)-prerelease"
{% endraw %}
```

Look at that! We used the `template syntax` just like when we defined the variable in the build YAML, but now set the default value for the `tags` parameter and get the same effect. And it can be overridden by the caller. It this is an ok default for the caller, this parameter can be omitted.

> Note that the tags uses macro syntax (runtime) for the default values. If we're not on main the parameter will look like this:
>
> ```yaml
>  - name: tags
>    type: string
>    default: "$(Build.BuildId)-prerelease"
> ```
>
> At runtime the `default` value will be set to the value of `Build.BuildId`, if it isn't passed in as a parameter. Cool 😇 feature or evil 😈 side effect? You decide.

Now let's add the steps from the build pipeline. In the YAML below, I did was copy the `steps` directly from the build pipeline's YAML. Now we need to review this YAML to see if we need to add more parameters.

```yaml
{% raw %}
steps:
- checkout: self
  displayName: 'Checkout source code'

- task: Docker@2
  displayName: Build and test sample-api    # 👈 The name is hard-coded!
  inputs:
    repository: sample-api                  # 👈 name, again
    command: build
    Dockerfile: DevOps/Dockerfile           # 👈 more hardcoded values that may be ok
    buildContext: ./src                     # 👈
    tags: $(tags)                           # 👈 This is now a parameter
    # 👇 We can some of these parameters, rely on standards for others
    arguments: >-
      --build-arg BUILD_VERSION=$(Build.BuildNumber)
      --target build-test-output
      --output $(Agent.TempDirectory)/output

- task: PublishPipelineArtifact@1
  displayName: 'Publish build log'
  inputs:
    targetPath: $(Agent.TempDirectory)/output/logs
    artifact: buildLog
  condition: succeededOrFailed()

- task: PublishTestResults@2
  displayName: 'Publish Test Results'
  inputs:
    testResultsFormat: VSTest
    testResultsFiles: '**/*.trx'
    searchFolder: $(Agent.TempDirectory)/output/testResults
    publishRunAttachments: true
    failTaskOnFailedTests: true

- task: PublishCodeCoverageResults@2
  displayName: 'Publish coverage reports'
  inputs:
    codeCoverageTool: 'cobertura'
    summaryFileLocation: $(Agent.TempDirectory)/output/testResults/coverage/coverage.cobertura.xml

- ${{ if not(parameters.isDryRun) }}:
  - task: Docker@2
    displayName: Publish my-sample-api  # 👈 name, again
    inputs:
      repository: my-sample-api         # 👈 name, again
      command: build
      Dockerfile: $(Agent.TempDirectory)/Dockerfile
      buildContext: ./src
      tags: $(tags)                     # 👈 tags again
      arguments: --build-arg BUILD_VERSION=$(Build.BuildNumber)

  - task: Docker@2
    displayName: Push my-sample-api Image to the ACR
    inputs:
      repository: my-sample-api        # 👈 name, again
      command: push
      tags: $(tags)                    # 👈 tags again
{% endraw %}
```

> A word about `$(tags)`. That will work, as long as the caller has set a variable `tags`. That is the equivalent to to using a global variable, which we all know are evil. It's best to use a parameter instead of macro syntax in a `steps` template. You can use it in `jobs` or `stages` templates, *if* you defined the variable in the template.

Adding a few parameters, clears all that up. If the caller conforms to our typical project layout, the only parameters needed are `isDryRun` and `repositoryName`

```yaml
{% raw %}
parameters:
  ...
  - name: repositoryName
    type: string

  - name: dockerfile
    type: string
    default: 'DevOps/Dockerfile'

  - name: context
    type: string
    default: './src'

  - name: buildNumber
    type: string
    default: '$(Build.BuildNumber)'

steps:
  - checkout: self
    displayName: 'Checkout source code'

  - task: Docker@2
    displayName: Build and test ${{ parameters.repositoryName }} # ✅
    inputs:
      repository: ${{ parameters.repositoryName }}               # ✅
      command: build
      Dockerfile: ${{ parameters.dockerfile }}                   # ✅
      buildContext: ${{ parameters.context }}                    # ✅
      tags: ${{ parameters.tags }}                               # ✅
      #                           👇 ✅
      arguments: >-
        --build-arg BUILD_VERSION=${{ parameters.buildNumber }}
        --target build-test-output
        --output $(Agent.TempDirectory)/output

  - task: PublishPipelineArtifact@1
    displayName: 'Publish build log'
    inputs:
      targetPath: $(Agent.TempDirectory)/output/logs
      artifact: buildLog
    condition: succeededOrFailed()

  - task: PublishTestResults@2
    displayName: 'Publish Test Results'
    inputs:
      testResultsFormat: VSTest
      testResultsFiles: '**/*.trx'
      searchFolder: $(Agent.TempDirectory)/output/testResults
      publishRunAttachments: true
      failTaskOnFailedTests: true

  - task: PublishCodeCoverageResults@2
    displayName: 'Publish coverage reports'
    inputs:
      codeCoverageTool: 'cobertura'
      summaryFileLocation: $(Agent.TempDirectory)/output/testResults/coverage/coverage.cobertura.xml

  - task: Docker@2
    displayName: Publish ${{ parameters.repositoryName }}     # ✅
    inputs:
      repository: ${{ parameters.repositoryName }}            # ✅
      command: build
      Dockerfile: ${{ parameters.dockerfile }}                # ✅
      buildContext: ${{ parameters.context }}                 # ✅
      tags: ${{ parameters.tags }}                            # ✅
      arguments: --build-arg BUILD_VERSION=${{ parameters.buildNumber }} # ✅

  - ${{ if not(parameters.isDryRun) }}:
    - task: Docker@2
      displayName: Push ${{ parameters.repositoryName }} Image to the ACR
      inputs:
        repository: ${{ parameters.repositoryName }}           # ✅
        command: push
        tags: ${{ parameters.tags }}                           # ✅
{% endraw %}
```

What if some apps don't create unit test output, or they have special parameters they need to pass into their build? They can't use this template. But wait! Why not more parameters?

```yaml
{% raw %}
  - name: dockerBuildArguments
    type: string
    displayName: Any additional arguments for docker build

  - name: dockerBuildOutputArguments
    type: string
    displayName: Any additional arguments for docker output part of build
    default: --target output --output $(Agent.TempDirectory)/output
{% endraw %}
```

And then update our Docker tasks to use these parameters. If `buildOutputArguments` is empty we'll totally skip the build and test step.

```yaml
{% raw %}
  # 👇 make it conditional to do build and test
  - ${{ if ne(replace(parameters.buildOutputArguments,' ',''), '') }}:
      - task: Docker@2
        displayName: Build and test ${{ parameters.repositoryName }}
        inputs:
          containerRegistry: ${{ parameters.registry }}
          repository: ${{ parameters.repositoryName }}
          command: build
          Dockerfile: ${{ parameters.dockerfile }}
          buildContext: ${{ parameters.context }}
          tags: ${{ parameters.tags }}
          arguments: ${{ parameters.buildArguments }} ${{ parameters.buildOutputArguments }} # 👈 add arguments

  # 👇 this will still build if needed
  - task: Docker@2
    displayName: Publish ${{ parameters.repositoryName }}
    inputs:
      repository: ${{ parameters.repositoryName }}
      command: build
      Dockerfile: ${{ parameters.dockerfile }}
      buildContext: ${{ parameters.context }}
      tags: ${{ parameters.tags }}
      arguments: arguments: ${{ parameters.buildArguments }} # 👈 add arguments

{% endraw %}
```

### Calling The Build Template

Now that we have a template, let's revamp the old build pipeline to use it.

```yaml
{% raw %}
name: '1.1.$(Rev:r)$(buildSuffix)'

parameters:
  - name: isDryRun
    type: boolean
    displayName: Perform a dry run - do not push the docker image
    default: true # for the blog sample testing we always do dry run
    # default: false

trigger:
  branches:
    include:
      - refs/heads/main
      - refs/heads/develop
      - refs/heads/release/*
  paths:
    exclude:
      - 'DevOps'
      - 'doc'
      - '*.md'
      - '*.ps*1'

pr:
  branches:
    include:
      - refs/heads/main
      - refs/heads/develop
  paths:
    exclude:
      - 'DevOps'
      - 'doc'
      - '*.md'
      - '*.ps*1'

variables:
  - name: buildSuffix
    # Set the build suffix to DRY RUN if it's a dry run, that is used in the name
    ${{ if parameters.isDryRun }}:
      value: '-DRYRUN'
    ${{ else }}:
      value: ''
  # ❌ deleted the tags variable, it's now a default parameter in the template

# 👇 add the template repository
resources:
  repositories:
    - repository: templates         # name after the @ below
      type: git
      name: azdo-templates
      ref: releases/v1.0

jobs:
  - job: build
    displayName: Build
    pool:
      vmImage: ubuntu-latest

    steps:
      # 👇 ripped out all the steps and added the template
      - template: steps/build.yml@templates
        parameters:
          isDryRun: ${{ parameters.isDryRun }}
          repositoryName: sample-api
          # 👇 these are optional, and I like the defaults
          # tags: # conditionally set
          # dockerfile: 'DevOps/Dockerfile'
          # context: './src'
          # buildNumber: '$(Build.BuildNumber)'
{% endraw %}
```

Now we can run the build pipeline just as before. The interesting part to this exercise it that the expanded YAML for the templated and non-templated pipelines are the same! We just made the pipeline more reusable. Here's the view of the templated pipeline, and you see all of the steps are the same as the original pipeline.

## Links

Azure DevOps documentation:

- [Templates](https://learn.microsoft.com/en-us/azure/devops/pipelines/process/templates?view=azure-devops&pivots=templates-includes)
- [Template Parameters](https://learn.microsoft.com/en-us/azure/devops/pipelines/process/template-parameters?view=azure-devops)