---
title: Typical Kubernetes Build and Deploy Azure DevOps Pipelines
tags:
 - devops
 - yaml
 - pipeline
 - build
 - deploy
excerpt: Building a Docker Image and deploying it
cover: /assets/images/leaf1.png
comments: true
layout: article
key: 20240810
---
{% assign sBrace = '{{' %}
{% assign eBrace = '}}' %}

![image]({{ page.cover }}){: width="{{ site.imageWidth }}" }

This is the first in a series of blog posts about creating standard Azure DevOps YAML pipelines across many projects. I tried to make this as generic as possible so you can adapt it to your project. In these posts I'll build a containerized .NET API with unit tests, and do a faked out deployments. The first post creates pipelines as one-offs. The second posts leverages templates to create a reusable library of pipeline steps. The third post will take using templates to the next level by creating a dynamic pipeline.

1. Typical Build and Deploy Azure DevOps Pipelines (this post)
1. [Moving Azure DevOps Pipelines Logic to a Template Repository]()
1. [Creating a Dynamic Azure DevOps Pipeline]()
1. [Azure DevOps Pipeline Tips, Tricks, Gotchas, and Headaches]()

> 💁 I walk through the build and deploy process from the beginning, but I assume you are familiar with the basic application lifecycle concepts for containerized applications.

## The Problem

I have built a containerized application that works fine locally. Now I want to create a CI/CD pipeline to build it and deploy it using Azure DevOps (AzDO) YAML pipelines.

## The Solution

In this post I'll walk through creating a typical build and deploy pipelines using Azure DevOps YAML pipelines. This example is a simplified, generic version of pipelines I've used in the past. Since the application is containerized, it can be any tech stack, from .NET Core to Node.js to Python. The deployment is stubbed out in the examples, but you can deploy the image to Kubernetes via Helm, cloud services, etc.

You can build and deploy in one pipeline, but I have learned from painful experience that it's better separate them. The main reason is that now that the pipeline code (YAML) is in source control, when it's 3am and you're doing a deploy to production only to discover a bug in your deploy pipeline or configuration, you do not want to do a new build. With a separate deploy pipeline, you can fix just the deploy YAML without having to rebuild the app.

### Folder Structure

I like to keep all my build- and deploy-related files in a `DevOps` folder in the root of the repository. If I have multiple deployables, I'll create a subfolder for each one under `DevOps`. Here's the folder structure for this example.

```text
├── DevOps
│   ├── build.yml                   # The AzDO build pipeline
│   ├── deploy.yml                  # The AzDO deploy pipeline
│   ├── Dockerfile                  # The Dockerfile to build
│   ├── values.yaml                 # Helm values file
│   └── variables
│       ├── blue.yml                # Variables for the blue environment
│       ├── green.yml               # Variables for the green environment
│       └── red.yml                 # Variables for the red environment
├── README.md
├── run.ps1                         # A helper to build, run, etc, locally.
└── src                             # Context folder for the Docker build
    ├── test-api.sln
    ├── test-api                    # Source for the test-api .NET Core app
    ├── test
    │   └── unit                    # Unit tests for the test-api
    └── .dockerignore               # This must be in the Docker context folder
```

> All my projects have a `run.ps1` file that has a bunch of CLI snippets to build, run, test, build docker, etc. locally. Instead of cutting and pasting command line snippets, they're all in this file and you just do something like `./run.ps1 build,run`. [Here's](https://gist.github.com/Seekatar/1197dff88d1126e9196e37a8b38f76bd) a typical one. I use `run.ps1` on Mac and Linux, too!

### 💁 Brief Lesson on Pipelines

The structure of a pipeline is shown below. By default, `stages` run sequentially and `jobs` run in parallel, but you can change that via `depends`. If your pipeline only has jobs, you can omit the `stages` section. If it only has `steps`, you can omit the `stages` and `jobs` sections. Even if you only have `steps` you may want to include `jobs` just to give the `job` a name, otherwise it will be named `Job`. I'll use `variables` in the pipelines. They can be defined at the pipeline, `stage`, or `job` scope, and last one wins.

```yaml
variables:
  ...
stages:
  - stage:
    variables:
      ...
    jobs:
      - job:
        variables:
          ...
        steps:
          - script: echo "Hello, world!"
          - task: TaskName@1
```

### The Build Pipeline

The build pipeline will get the source code, build the Docker image, and push it to the container registry (if not a dry run). The build and unit tests are run in a multi-stage Dockerfile. See my blog post on [unit tests in Docker](/_site/_posts/2023-04-12-docker-dotnet-unittest.html) on how I build, test, and get the output from Docker.

#### Preamble

The first part of the pipeline is shown below, will explanation following. This sets up the pipeline before we actually start doing anything.

```yaml
{% raw %}
name: '1.1.$(Rev:r)$(buildSuffix)'

parameters:
  - name: isDryRun
    type: boolean
    displayName: Perform a dry run - do not push the docker image
    default: false

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
  # image tags used below in the Docker tasks
  - name: tags
    # Add a prefix to the build number if it's not main
    ${{ if eq(variables['Build.SourceBranchName'],'main') }}:
      value: "$(Build.BuildId)"
    ${{ else }}:
      value: "$(Build.BuildId)-prerelease"

  - name: buildSuffix
    # Set the build suffix to DRY RUN if it's a dry run, that is used in the name
    ${{ if parameters.isDryRun }}:
      value: '-DRYRUN'
    ${{ else }}:
      value: ''
{% endraw %}
```

[name](https://learn.microsoft.com/en-us/azure/devops/pipelines/process/run-number?view=azure-devops) will be shown in the AzDO UI when the pipeline is run, and is available as a variable in the pipeline that you can use to tags your image, etc. In this example, I have a hard-coded `1.3.` that will be followed by the build number, `$(Rev:r)`. The `$(BuildSuffix)` will be empty unless it is a dry run, in which case it will be `-DRY RUN` to make it obvious in the UI. The [documentation](https://learn.microsoft.com/en-us/azure/devops/pipelines/process/run-number?view=azure-devops#tokens) shows all the various variables you can use in the name, such as parts of the date, etc.

> 💁 The `$(Rev:r)` is a build number that is incremented each time the pipeline is run. If you re-create the pipeline, the build number will start over at 1, which can be a problem if you use that to tag your image or library. In that case you'll have to change the hard-coded part of the name.

[parameters](https://learn.microsoft.com/en-us/azure/devops/pipelines/yaml-schema/parameters?view=azure-pipelines) are values you can set when the pipeline is run manually. A CI run will use the default value, but you can use `parameters` to allow a user to override that value in a one-off run. In this case I allow the user to kick off a build without pushing the Docker image to the registry.

[trigger](https://learn.microsoft.com/en-us/azure/devops/pipelines/yaml-schema/trigger?view=azure-pipelines) and [pr](https://learn.microsoft.com/en-us/azure/devops/pipelines/yaml-schema/pr?view=azure-pipelines) are configured identically. The `trigger` section tells AzDO when to run the pipeline when code is merged or committed to those branches. As the name suggests, `pr` is for pull requests. You can use `none` to disable the trigger.

If you have multiple deployables in the same repository, you can use `paths.include` to include only the source code for that deployable. Take time to get the `paths` right, as you don't want to build and deploy every time someone updates the README or some other code that is not part of the build. If you want to test path `paths.include` and `exclude`, you can temporarily add your feature branch to the `branches.include` list.

> 💁 Brief Lesson on Variable Syntax
>
> There are three [syntax](https://learn.microsoft.com/en-us/azure/devops/pipelines/process/variables?view=azure-devops&tabs=yaml%2Cbatch#understand-variable-syntax) types used in AzDO YAML. In these examples I use the `template expression syntax` (aka `template syntax`), which is `${{sBrace}} ... {{eBrace}}` and the macro syntax, which is `$(...)`.
>
> The `template syntax` is evaluated when the YAML is processed at build time similar to pre-processor directives in a language like C++. When you view expanded YAML in the AzDO UI, you will never see the template syntax since it it replaced with the actual value.
>
> The `macro` syntax is evaluated at runtime. When you view expanded YAML, it will have `$(myName)` in it since it's not until the step is executed that it is replaced with the actual value. If the variable `myname` doesn't exist at runtime then `$(myName)` will left in the YAML, which may be what you want if it's in shell script code.
>

In the preamble I use several predefined variables, such as `$(Build.BuildId)` and `$(buldSuffix)`. The former is a [predefined variable](https://learn.microsoft.com/en-us/azure/devops/pipelines/build/variables), of which there are many. The second is one I set below in the `variables` section. Notice that the `template syntax` also has [conditional statements](https://learn.microsoft.com/en-us/azure/devops/pipelines/process/expressions?view=azure-devops#conditional-insertion), (`if`, `else`, `elseif`) that I use to set the values of the variables depending on other variables. I'll use `each` in the deploy pipeline.

#### The Work

The build only has one job, so I omit `stages`. I could omit `jobs` and just have `steps`, but I like to give the job a `displayName`.

```yaml
{% raw %}
jobs:
  - job: build
    displayName: Build
    pool:
      vmImage: ubuntu-latest

    steps:
      - checkout: self
        displayName: 'Checkout source code'

      - task: Docker@2
        displayName: Build and test my-test-api
        inputs:
          repository: test-api
          command: build
          Dockerfile: DevOps/Dockerfile
          buildContext: ./src
          tags: $(tags)
          arguments: --build-arg BUILD_VERSION=$(Build.BuildNumber) --target build-test-output --output $(Agent.TempDirectory)/output

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
          displayName: Publish my-test-api
          inputs:
            repository: my-test-api
            command: build
            Dockerfile: $(Agent.TempDirectory)/Dockerfile
            buildContext: ./src
            tags: $(tags)
            arguments: --build-arg BUILD_VERSION=$(Build.BuildNumber)

        - task: Docker@2
          displayName: Push my-test-api Image to the ACR
          inputs:
            repository: my-test-api
            command: push
            tags: $(tags)
{% endraw %}
```

[job](https://learn.microsoft.com/en-us/azure/devops/pipelines/yaml-schema/jobs-job?view=azure-pipelines) has an optional id, which is just `build` in this case. The id can be used to set up dependencies, or get output from one job into another (stay tuned for a later blog post).

[pool](https://learn.microsoft.com/en-us/azure/devops/pipelines/yaml-schema/pool?view=azure-pipelines) is the agent pool (Virtual Machine type) this job will run on. All the steps in this job run on the same agent (VM) in sequence. Often a company will have its own agent pool of VMs with particular software installed, networks access, etc.

[steps](https://learn.microsoft.com/en-us/azure/devops/pipelines/yaml-schema/steps?view=azure-pipelines) are where we finally start running tasks for our pipeline. If you edit a pipeline in the AzDO UI, you can search for tasks your organization has installed and see their parameters, and add its YAML. Using an editor like VS Code you don't get that, even using the extension. When I need to add a task I haven't used before, I add it in the UI and paste the YAML into VS Code.

Most steps you run are a `task`, but there are some built in ones such as `checkout`,`bash`, `pwsh`, etc. as described in the link above. Regardless, each task will have following properties:

- `displayName` is what will be shown in the AzDO UI when it runs.
- `inputs` are the parameters for the task.
- [`condition`](https://learn.microsoft.com/en-us/azure/devops/pipelines/process/conditions?view=azure-devops&tabs=yaml%2Cstages) controls whether the task is run or not, and defaults to `succeeded()`. That means the task will run only if the previous task succeeded. In the example above, I run the tasks that publish the build output even if the build failed.

The `displayName`s above give a good idea of what each task is doing. You may wonder why is `Docker@2` used three times. This is due to the way my multistage Dockerfile runs that allows me to get the build and unit test output from Docker (see [this](/_site/_posts/2023-04-12-docker-dotnet-unittest.html) post). The first one does the `build` command to do a build and run unittest stages writing the output to `$(Agent.TempDirectory)/output`. The second one does the `build` to create the final image. The third one does the `push` command to push the image to the container registry.

If this was building a library such as a .NET NuGet or npm package, it would be using a different build steps, and there would be no deploy pipeline.

### The Deploy Pipeline

The deploy pipeline will get the Docker image from the container registry and deploy it. Most companies you will have multiple environments, such as test, dev, staging, production, etc. I prefer the build-once-deploy-everywhere model. Of course, you have different configuration values for each environment that you need to set, such as in a Helm `values.yaml` file. You can use a separate `values.yaml` file for each environment, but that creates maintenance issues. I use one `values.yaml` file that has placeholders for the environment-specific values that get set at deploy time.

In the sample, I use `stages` to deploy to red, green, and blue environments sequentially, which is the default. You can add `depends` to a `stage` to change the graph of the stages. To make things a bit interesting, each one has some different values in their `DevOps/variables/<env>-environment.yml` file that are set in the `values.yaml` file.

#### Preamble

The preamble is similar to the build pipeline. The main difference is this is never triggered by a commit, instead it is triggered by the build pipeline, which is added in the `resources` section.

```yaml
name: '1.1.$(Rev:r)-$(DeploySuffix)'

parameters:
- name: environments
  type: object
  displayName: Environments to deploy to
  default:
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
    source: build_test-api    # MUST match the AzDO build pipeline name
    trigger:
      branches:
        include:
          - main              # Only trigger a deploy from the main branch build
```

[trigger](https://learn.microsoft.com/en-us/azure/devops/pipelines/yaml-schema/trigger?view=azure-pipelines) and [pr](https://learn.microsoft.com/en-us/azure/devops/pipelines/yaml-schema/pr?view=azure-pipelines) are disabled for the deploy pipeline since we never want to run it when code changes.

[resources.pipelines.pipeline](https://learn.microsoft.com/en-us/azure/devops/pipelines/yaml-schema/resources-pipelines-pipeline?view=azure-pipelines) is how we trigger the deploy pipeline from the build pipeline. The `source` is the name you give the build pipeline when you creating it in AzDO. In the `trigger` section I limit running the deploy pipeline only when a `main` branch build is run.

There are other types of resources, which I'll cover in a later blog post.

#### The Work

Since the deployment YAML to each environment is identical, I use an `${{sBrace}}each{{eBrace}}` loop to deploy to each environment. For any differences between environments that can't be handled by simply using the `env` variable, I include a separate yaml file for each environment.

There's not too much to the deployment, and this sample is stubbed out. In general, a Helm deploy will have the following steps:

1. Get the secrets from the secret store to connect to K8s.
2. Connect to the K8s cluster.
3. Replace the placeholders in the `values.yaml` file with the environment-specific values. (Or you can use separate `values-<env>.yaml` files 🤮)
4. Deploy the Helm chart.

> There is a [Helm task](https://learn.microsoft.com/en-us/azure/devops/pipelines/tasks/reference/helm-deploy-v0?view=azure-pipelines) but I found that it didn't handle failures very well. If a deploy pipeline failed to deploy to K8s, you just get a timeout. To get better error handling, I wrote a PowerShell module, [K8sUtils](https://www.powershellgallery.com/packages/K8sUtils), that does a Helm install, but captures all the events, and logs from the deploy and fails on the first error. With the Helm task, even if the deploy failed immediately in K8s, it would wait until the timeout before returning. Using module has made life much easier in my current situation.

```yaml
{% raw %}
stages:
- ${{ each env in parameters.environments }}: # create this stage for each environment
  - stage: deploy_${{ lower(env) }}           # stage names must be unique
    displayName: Deploy ${{ env }}

    variables:
      - name: appName
        value: test-api
      - name: envLower
        value: ${{ lower(env) }}
      - name: imageTag  # substituted in values.yaml
        value: $(resources.pipeline.build_pipeline.runID)
      - name: valueFileName
        value: values.yaml

      - template: variables/${{ variables.envLower }}-environment.yml # Load the environment variables specific to this environment

    jobs:
    - job: deploy_${{ variables.envLower }}           # job names must be unique
      displayName: Deploy ${{env }}
      pool:
        vmImage: ubuntu-latest

      steps:
      # - task: AzureKeyVault@2 # A task to get secrets for the K8s login step below

      # - task: Kubernetes@1    # To deploy with Helm, we need to connect to the cluster

      - task: qetza.replacetokens.replacetokens-task.replacetokens@5
        displayName: 'Replacing #{VAR}#. Will error on missing variables'
        inputs:
          targetFiles: ./DevOps/values.yaml => $(Agent.TempDirectory)/$(valueFileName)
          actionOnMissing: fail

      - pwsh: |
          Get-Content $(Agent.TempDirectory)/$(valueFileName)
        displayName: 'Show Helm Values'

      - pwsh: |
          if ($env:isDryRun -eq 'true') {
            Write-Host "This is a dry run. No deployment will be done."
          } else {
            Write-Host "Deploying to $envLower"
          }
          Write-Host "This is a fake deployment step. Using K8sUtils and helm is a great way to deploy to Kubernetes"
        displayName: Deploy $(appName)
        env:
          isDryRun: $(isDryRun)
{% endraw %}
```

This is where YAML really shines. Since each deployment is identical, I can re-use the YAML by using an {{sBrace}}each{{eBrace}} loop. The `parameters.environments` is an array of environments to deploy to, which can be overridden for manually deploying to any environment. Inside the loop the `env` variable will have the name of the current environment. In the default case it will replicate the `stage` for each environment.

Since each environment may have different settings, I include different variables for each one via the `template` keyword under `stage.variables`. (I'll get more into templates in a later blog post.) In this case, I have a YAML file per environment and using a naming convention I can include the correct one for the each environment. The variables in these files are used to replace the placeholders in the `values.yaml` file avoiding the need for separate `values-<env>.yaml` files.

The replacement step uses a [third-party](https://marketplace.visualstudio.com/items?itemName=qetza.replacetokens) task you can install in you AzDO organization. You may use another, or roll your own (like [this]()) but using something like this is a good idea. The odd `./DevOps/values.yaml => $(Agent.TempDirectory)/$(valueFileName)` syntax tells it not to overwrite the original file. I had a problem in one pipeline that did multiple deploys using the same `values.yaml` file, and the second replacement step would do nothing since all the placeholders were already replaced (with the values I don't want in the second one!).

The `Show Helm Values` step is a debugging aid. If we had problems in a deployment, by looking at the values file after the substitutions we could often spot it (usually a YAML indenting issue). Alternatively, you could save the file as a pipeline artifact.

### Creating and Running the Pipelines

You should create your YAML on a feature branch and test it before merging it to the main branch. Chances are you will have to make several fixes to get a clean run (this is YAML) and you don't want to be doing a bunch of PRs, etc. My process is

1. Create the YAML on a feature branch.
1. Commit and push the YAML.
1. Create the build pipeline in AzDO UI. See [this]() post for step-by-step instructions, including Validating the YAML.
1. Create the deploy pipeline in AzDO UI. Remember its `resources.pipelines.pipeline.source` must match the name from the previous step.
1. Run the build pipeline. Fix, repeat, until green.
1. Run the deploy pipeline. Fix, repeat, until green.
1. Merge to your main branch!

There are some things to know when running the deploy pipeline.

1. The deploy pipeline will deploy the _latest_ build by default. When triggered by the build pipeline, this is what you want. For manual deploys, you may pick the build to deploy by clicking the `Resources` button in the UI and selecting the build from the list. This is why I tack on `-DRY RUN` to dry run build names to make it obvious you don't want that build.
1. There's a bit of a trick to getting the deploy kicked off from the build pipeline. As of this writing, a pipeline must be committed to the default branch to trigger. Once the deploy pipeline is in your default branch it should trigger. Later you can edit and trigger from a branch. See the [documentation](https://learn.microsoft.com/en-us/azure/devops/pipelines/process/pipeline-triggers?view=azure-devops&tabs=yaml#branch-considerations) for details.

## Summary

I hope this will help you get started building your own YAML pipelines. This blog has shown the way to get a basic build and deploy up and running as a one-off. In the next post, I'll show how to take this YAML and create reusable `template`s that you can use across many projects.

## Links

- [This sample's source](https://dev.azure.com/MrSeekatar/SeekatarBlog/_git/TypicalPipeline)
- [This sample's Build pipeline in Azure DevOps](https://dev.azure.com/MrSeekatar/SeekatarBlog/_build?definitionId=49)
- [This sample's Deploy pipeline in Azure DevOps](https://dev.azure.com/MrSeekatar/SeekatarBlog/_build?definitionId=50)
- [Running .NET Unit tests in Docker](https://seekatar.github.io/2023/04/12/docker-dotnet-unittest.html) my blog post on how I run unit tests in Docker and get output.

Gists:

- [Replace-It.ps1]() - A PowerShell script to replace placeholders in a file with values from a file.
- [run.ps1](https://gist.github.com/Seekatar/1197dff88d1126e9196e37a8b38f76bd) - A PowerShell script to build, run, test, build docker, etc. locally.

Docker documentation:

- [Build Context](https://docs.docker.com/build/concepts/context/)
- [.dockerignore](https://docs.docker.com/build/concepts/context/#dockerignore-files)

Azure DevOps documentation:

- [Run and Build Numbers (pipeline name)](https://learn.microsoft.com/en-us/azure/devops/pipelines/process/run-number?view=azure-devops)
- [Conditions](https://learn.microsoft.com/en-us/azure/devops/pipelines/process/conditions?view=azure-devops&tabs=yaml%2Cstages)
- [Predefined Build Variables](https://learn.microsoft.com/en-us/azure/devops/pipelines/build/variables?view=azure-devops&tabs=yaml#build-variables-devops-services)
- [Predefined System Variables](https://learn.microsoft.com/en-us/azure/devops/pipelines/build/variables?view=azure-devops&tabs=yaml#system-variables-devops-services)
