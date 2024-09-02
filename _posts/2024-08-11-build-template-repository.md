---
title: Creating a Build Pipeline Template
tags:
 - devops
 - yaml
 - build
 - pipeline
 - templates
 - azure-devops
excerpt: Moving Azure DevOps build logic to a template repository
cover: /assets/images/leaf2.png
comments: true
layout: article
key: 20240811build
---

![image]({{ page.cover }}){: width="{{ site.imageWidth }}" }

This is the second in a series of posts about creating reusable Azure DevOps YAML pipelines across many projects. In these posts, I'll start with simple CI/CD pipelines and progress to a complex, dynamic pipeline.

1. [CI/CD YAML Pipelines](/2024/08/10/typical-pipeline.html)
1. Creating a Build Pipeline Template (this post)
1. [Creating a Deploy Pipeline Template](/2024/08/21/deploy-template-repository.html)
1. [Using `extends` and "feature flags" in a pipeline](/2024/08/15/extends.html)
1. [Dynamic CI/CD Pipeline](/2024/08/21/build-pipeline.html)
1. [Azure DevOps Pipeline Tips and Tricks](/2024/08/22/azdo-tat.html)

> 💁 I assume you have read the previous blog and are familiar with the basic application lifecycle concepts for containerized applications.

The YAML, sample source code, and pipelines are all in [this](https://dev.azure.com/MrSeekatar/SeekatarBlog/_git/TypicalPipeline) AzDO Project.

## The Problem

Now that I have a nice set of YAML CI/CD pipelines, I want to reuse them across my organization. Many of my applications are similar, and they all build Docker images.

## The Solution

In this post, I'll take the build YAML from the previous post, and move chunks of YAML (templates) into a separate repository. Then I can use those chunks in pipelines across my organization. By having one central location, I can make changes and fixes to the shared YAML and all the pipelines that use it get updated.

> 💁 Brief Lesson on Templates
>
> [Templates](https://learn.microsoft.com/en-us/azure/devops/pipelines/process/templates?view=azure-devops&pivots=templates-includes) are chunks of YAML that can be included in other YAML files, similar to `#include` in C++. In this post I'll use the term `template` to refer to `Includes Templates` (I'll cover `Extends Templates` in the next post).
>
> Each template contains one type of AzDO object, such as a `stages`, `jobs`, `steps`, or `variables`. One of those keywords will be in each file, and it can only be used under the same keyword. E.g if the template has `steps` it can only go under `steps` in the calling YAML. Templates can have [parameters](https://learn.microsoft.com/en-us/azure/devops/pipelines/process/template-parameters?view=azure-devops), so you can make them as flexible as possible.
>

I used a template in the first post to pull in the variables for the pipeline. In that case, the template was in the same repo as the caller. In this post, the templates will be in a separate repo.

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

Notice when I reference the `azdo-templates` repository, I use a branch name of `releases/v1.0`. The `main` branch of the template repo is always the latest branch and will be in sync with the highest numbered `releases` branch. The process of making changes to the template is as follows:

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

That list of tasks is what any Docker build runs. Let's see how to make that a `template`. I could make the `template` a `stage`, `job`, or `steps`. Usually, you want the template library to be a bunch of smaller Lego-like pieces that can be combined into larger templates, or used by themselves. I'll make this one `steps` since that way it can be used in any `job`, or using multiple times in one `job`. I can always wrap it in a `job` template if I need to.

The original pipeline had a dry run parameter, so I'll need that. Then, since this template will go under `steps` in the calling pipeline, I'll add `steps` to the template.

```yaml
parameters:
  - name: isDryRun
    type: boolean

steps:
```

I don't have a `default` or `displayName` for the parameter, since the name makes it obvious, and it will never be shown in the UI. I'll always want the caller to pass in the parameter, so it has no default.

In the build pipeline, I set the tags variable like this:

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

`steps` can't contain `variables` so we can't do the same thing. Instead, we'll add another parameter `tags`. You may think, why can't I set the `default` value for the parameter like I did for the `value` of the variable? Unfortunately, the template syntax is not allowed in `parameters`

Now I’ll add the steps from the build pipeline. In the YAML below, I copied the `steps` from the build pipeline's YAML. Next, I need to review this YAML to see if we need to add more parameters.

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
    # 👇 We can make some of these parameters, rely on standards for others
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

> A word about `$(tags)`. That will work, as long as the caller has set a variable `tags`. That is equivalent to using a global variable, which we all know is evil. It's best to use a parameter instead of macro syntax in a `steps` template. You can use it in `jobs` or `stages` templates, *if* you defined the variable in the template.

Adding a few parameters clears all that up. If the caller conforms to our typical project layout, the only parameters needed are `isDryRun` and `repositoryName`.

```yaml
{% raw %}
parameters:
  ...
  - name: repositoryName
    type: string

  - name: tags
    type: string
    displayName: Comma-separated tags for the docker image # 👈 displayName tells the expected format

- name: buildNumber
    type: string
    default: '$(Build.BuildNumber)'

  - name: context
    type: string
    default: './src'

  - name: dockerfile
      type: string
      default: 'DevOps/Dockerfile'

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

> Note that the `buildNumber` uses macro syntax (runtime) for the default values. If the caller does not pass in `buildNumber` at runtime, it will use the value of the predefined variable `$(Build.BuildNumber)` You can use any variable that is defined as the default, but as mentioned above, use care with global variables.
>
> Is using macro syntax for default parameters a cool 😇 feature or evil 😈 side effect? You decide.

What if some apps don't create unit test output or have special parameters to pass into their build? They can't use this template. But wait! Why not add more parameters?

```yaml
{% raw %}
  - name: dockerBuildArguments
    type: string
    displayName: Any additional arguments for docker build
    default: '--build-arg BUILD_VERSION=$(Build.BuildNumber)'

  - name: dockerBuildOutputArguments
    type: string
    displayName: Output arguments for docker build, leave empty if no unit test output from Docker
    default: '--target output --output $(Agent.TempDirectory)/output'
{% endraw %}
```

I use `displayName` in this case to better explain the parameter.

Next, I update the Docker tasks to use these parameters. If `buildOutputArguments` is empty it will skip the build and test step.

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
      arguments: ${{ parameters.buildArguments }} # 👈 add arguments

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
  - name: tags
    ${{ if eq(variables['Build.SourceBranchName'],'main') }}:
      value: "$(Build.BuildId)"
    ${{ else }}:
      value: "$(Build.BuildId)-prerelease"

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
          tags: $(tags)
          # 👇 these are optional, and I like the defaults
          # dockerfile: 'DevOps/Dockerfile'
          # context: './src'
          # buildNumber: '$(Build.BuildNumber)'
{% endraw %}
```

Now we can run the build pipeline just as before. The interesting part of this exercise is that the expanded YAML for the templated and non-templated pipelines steps are the same! We just made the YAML reusable. Here's a screen shot of the original pipeline on the left and templated pipeline on the right.

![Comparing two build steps](/assets/images/devOpsBlogs/compare-builds.png)

From the completed job, if you use the kebab menu to `Download logs` and view the expanded YAML the only difference will be the added `resources` section. The `template` keyword is replaced with the steps from the template.

## Summary

In this post, I showed you have to take a build pipeline and create a template from it. Converting any YAML pipeline will follow the same steps. In the next post, I'll do that for the deploy pipeline.

## Links

Azure DevOps documentation:

- [Templates](https://learn.microsoft.com/en-us/azure/devops/pipelines/process/templates?view=azure-devops&pivots=templates-includes)
- [Template Parameters](https://learn.microsoft.com/en-us/azure/devops/pipelines/process/template-parameters?view=azure-devops)
