---
title: Typical Kubernetes Build and Deploy Azure DevOps Pipelines
tags:
 - devops
 - yaml
 - pipeline
 - build
 - deploy
excerpt: Building a Docker Image and deploying it to Kubernetes via Helm
cover: /assets/images/leaf-1408533.jpg
comments: true
layout: article
key: 20240810
---

![image]({{ page.cover }}){: width="{{ site.imageWidth }}" }

This is the first in a series of blog posts about creating a set of Azure DevOps YAML pipelines to standardize across many projects.

> [!NOTE]
> In this series I walk through the build and deploy process from the beginning, but I do assume you are familiar with the basic application lifecycle concepts.

1. Typical Kubernetes Build and Deploy Azure DevOps Pipelines
1. Moving Azure DevOps Pipelines Logic to a Template Repository
1. Creating a Dynamic Azure DevOps Pipeline
1. Azure DevOps Pipeline Tips, Tricks, Gotchas, and Headaches

## The Problem

I have built a containerized application that works find locally. Now I want to create a CI/CD pipeline to build it and deploy it to Kubernetes using Azure DevOps (AzDO) YAML pipelines.

## The Solution

In this post I'll walk through creating a typical build and deploy pipelines for a Kubernetes application using Azure DevOps YAML pipelines. This example is a simplified, generic version of pipelines I've used in the past. Since the application is containerized, it can be on any tech stack, from .NET Core to Node.js to Python.

You can build and deploy in one pipeline, but I have learned from painful experience that it's better separate them. The main reason is that now that the pipeline code is in source control, when it's 3am and you're doing a deploy to production and discover a bug in your deploy pipeline, you do not want to do a new build. With a separate deploy pipeline, you can fix just the deploy YAML without having to do a new build.

### Folder Structure

I like to keep all my build- and deploy-related files in a `DevOps` folder in the root of the repository. If I have multiple deployables, I'll create a subfolder for each one in `DevOps`. Here's the folder structure for this example.

```text
├── DevOps
│   ├── build.yml                   # The AzDO build pipeline
│   ├── deploy.yml                  # The AzDO deploy pipeline
│   ├── Dockerfile                  # The Dockerfile to build
│   ├── .dockerignore               # The .dockerignore file
│   ├── values.yaml                 # Helm values file
│   └── variables
│       ├── blue.yml                # Variables for the blue environment
│       ├── green.yml               # Variables for the green environment
│       └── red.yml                 # Variables for the red environment
├── README.md
├── run.ps1                         # A helper to build, run, etc. locally.
└── src                             # Context for the Docker build
```

It is important to note that the `.dockerignore` file must be in the [context](https://docs.docker.com/build/concepts/context/) folder when doing a `docker build`. I like to keep all the DevOps related files together, so in this case I must copy the `.dockerignore` file to the `src` folder when doing the build. You may want to keep the `.dockerignore` file in the `src` folder.

> All my projects have a `run.ps1` file that has a bunch of CLI snippets to build, run, test, build docker, etc. locally. Instead of cutting a pasting command line snippets, they're all in this file and you just do something like `./run.ps1 build,run`. [Here's](https://gist.github.com/Seekatar/1197dff88d1126e9196e37a8b38f76bd) a typical one. I use `run.ps1` on Mac and Linux, too!

### 💁 Brief Lesson on Pipelines

The structure of a pipeline is shown below. By default, `stages` run sequentially and `jobs` run in parallel, but you can change that via `depends`. If your pipeline only has `steps`, you can omit the `stages` and `jobs` sections. Like wise if you only have jobs, you can omit the `stages` section.

 ```yaml
 stages:
   - stage:
       jobs:
         - job:
           steps:
             - script: echo "Hello, world!"
             - task: TaskName@1
```

Even if you only have `steps` you may want to include `jobs` just to give it a name, otherwise it will be named `Job`.

### The Build Pipeline

The build pipeline will get the source code, build the Docker image, and push it to the container registry (if not a dry run). The build and unit tests are run in a multi-stage Dockerfile. See my blog post on [unit tests in Docker](/_site/_posts/2023-04-12-docker-dotnet-unittest.html) on how I build, test, and get the output.

#### Preamble

The first part of the pipeline is shown below. This sets up the pipeline before we actually start doing anything.

```yaml
name: '1.3.$(Rev:r)$(BuildSuffix)'

parameters:
  - name: isDryRun
    type: boolean
    displayName: Perform a dry run - do not push the docker image
    default: false

trigger:
  branches:
    include:
      - refs/heads/master
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
      - refs/heads/master
      - refs/heads/develop
  paths:
    exclude:
      - 'DevOps'
      - 'doc'
      - '*.md'
      - '*.ps*1'
```

[name](https://learn.microsoft.com/en-us/azure/devops/pipelines/process/run-number?view=azure-devops) will be shown in the AzDO UI when the pipeline is run, and is available as a variable in the pipeline that you can use to tags your image, etc. In this example, I have a hard-coded `1.3.` that will be followed by the build number, `$(Rev:r)`. The `$(BuildSuffix)` will be empty unless it is a dry run, in which case it will be `-DRY RUN` to make it obvious in the UI. The documentation shows all the various variables you can use in the name, such as parts of the date, etc.

> [!TIP]
> The `$(Rev:r)` is a build number that is incremented each time the pipeline is run. If you re-create the pipeline, the build number will start over at 1, which can be a problem if you use that to tag your image or library. In that case you'll have to change the hard-coded part of the name.

[parameters](https://learn.microsoft.com/en-us/azure/devops/pipelines/yaml-schema/parameters?view=azure-pipelines) are values you can set when the pipeline is run manually. The CI/CD will use the default value, but you can use `parameters` to allow a user to override that value in a one-off run. In this case I allow the user to kick off a build without pushing the Docker image to the registry.

[trigger](https://learn.microsoft.com/en-us/azure/devops/pipelines/yaml-schema/trigger?view=azure-pipelines) and [pr](https://learn.microsoft.com/en-us/azure/devops/pipelines/yaml-schema/pr?view=azure-pipelines) are configured identically. The `trigger` section tells AzDO when to run the pipeline when code is merged or committed to those branches. As the name suggests, `pr` is for pull requests. You can use `none` to disable the trigger.

If you have multiple deployables in the same repository, you can use `paths.include` to include only the source code for that deployable. Take time to get the `paths` right, as you don't want to build and deploy every time someone updates the README or some other code that is not part of the build.

#### The Work

The build only has one job, so I omit `stages`. I could omit `jobs` and just have `steps`, but I like to give the job a name.

```yaml
jobs:
  - job: build
    displayName: Build
    pool:
      vmImage: ubuntu-latest

    variables:
      # image tags used below in the Docker tasks
      - name: tags
        # Add a prefix to the build number if it's not master
        ${{ if eq(variables['Build.SourceBranchName'],'master') }}:
          value: "$(Build.BuildId)"
        ${{ else }}:
          value: "$(Build.BuildId)-prerelease"

      - name: buildSuffix
        # Set the build suffix to DRY RUN if it's a dry run, that is used in the name
        ${{ if parameters.isDryRun }}:
          value: '-DRYRUN'
        ${{ else }}:
          value: ''

    steps:
      - checkout: self
        displayName: 'Checkout source code'

      - task: Docker@2
        displayName: Build and test my-test-api
        inputs:
          containerRegistry: acr-service-connection
          repository: my-test-api
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
          searchFolder: $(Agent.TempDirectory)/output/testresults
          publishRunAttachments: true
          failTaskOnFailedTests: true

      - task: PublishCodeCoverageResults@2
        displayName: 'Publish coverage reports'
        inputs:
          codeCoverageTool: 'cobertura'
          summaryFileLocation: $(Agent.TempDirectory)/output/testresults/coverage/coverage.cobertura.xml

      - task: Docker@2
        displayName: Publish my-test-api
        inputs:
          containerRegistry: acr-service-connection
          repository: my-test-api
          command: build
          Dockerfile: $(Agent.TempDirectory)/Dockerfile
          buildContext: ./src
          tags: $(tags)
          arguments: --build-arg BUILD_VERSION=$(Build.BuildNumber)

      - task: Docker@2
        displayName: Push my-test-api Image to the ACR
        inputs:
          containerRegistry: acr-service-connection
          repository: my-test-api
          command: push
          tags: $(tags)
```

[job](https://learn.microsoft.com/en-us/azure/devops/pipelines/yaml-schema/jobs-job?view=azure-pipelines) has an optional id, which is just `build` in this case. The id can be used to set up dependencies, or get output from one job into another (stay tuned for a later blog post).

[pool](https://learn.microsoft.com/en-us/azure/devops/pipelines/yaml-schema/pool?view=azure-pipelines) is the agent pool (Virtual Machine type) this job will run on. All the steps in this job run on the same agent (VM) in sequence. Often a company will have its own agent pool of VMs with particular software installed, networks access, etc.

[steps](https://learn.microsoft.com/en-us/azure/devops/pipelines/yaml-schema/steps?view=azure-pipelines) are where we finally start running tasks for our pipeline. If you edit a pipeline in the AzDO UI, you can search for tasks and add the YAML for them. Using an editor like VS Code you don't get that, even using the extension. When I need to add a task I haven't used before, I add it in the UI and paste the YAML into VS Code.

Most steps you run are a `task`, but there are some built in ones such as `checkout`, `pwsh`, etc. as described in the link above. Regardless, each task will have following properties:

- `displayName` is what will be shown in the AzDO UI.
- `inputs` are the parameters for the task.
- [`condition`](https://learn.microsoft.com/en-us/azure/devops/pipelines/process/conditions?view=azure-devops&tabs=yaml%2Cstages) controls where the task is run or not, and defaults to `succeeded()`. That means the task will run only if the previous task succeeded. In the example above, I run the tasks that publish the build output even if the build failed.

The `displayName`s above give a good idea of what each task is doing. You may wonder why is `Docker@2` used three times. This is due to the way my multistage Dockerfile runs that allows me to get the build and unit test output from Docker (see [this](/_site/_posts/2023-04-12-docker-dotnet-unittest.html) post). The first one does the `build` command to do a build and run unittest stages writing the output to `$(Agent.TempDirectory)/output`. The second one does the `build` to create the final image. The third one does the `push` command to push the image to the container registry.

If this was just building a library such as a .NET NuGet or npm package, it would be using a different build steps, and there would be no deploy pipeline.

> 💁 Brief Lesson on Variable Syntax
>
> There are three [syntax](https://learn.microsoft.com/en-us/azure/devops/pipelines/process/variables?view=azure-devops&tabs=yaml%2Cbatch#understand-variable-syntax) types used in AzDO YAML. In these examples I use the `template expression` (aka `template`) syntax, which is `${{ ... }}` and the macro syntax, which is `$(...)`.
> The `macro` syntax is evaluated at runtime. If you look at the YAML for the pipeline, it will have `$(myName)` in it since it's not until the step is executed that it is replaced with the actual value. If the variable `myname` is not set then `$(myName)` will left in the YAML, which may be what you want if it's in shell script code.
>
> The `template` syntax, which I use in the deploy pipeline, is evaluated when the YAML is processed at build time similar to pre-processor directives in a language like C++.

In the build pipeline I use several predefined variables, such as `$(Build.BuildId)` and `$(Agent.TempDirectory)`. The list of predefined variables, of which there are many, is [here](https://learn.microsoft.com/en-us/azure/devops/pipelines/build/variables).

### The Deploy Pipeline

The deploy pipeline will get the Docker image from the container registry and deploy it to Kubernetes using Helm. In most companies you will have multiple environments, such as test, dev, staging, production, etc. I prefer the build-once deploy everywhere model. Of course, you have different configuration values for each environment that you need to set in Helm via the `values.yaml` file. You can use a separate `values.yaml` file for each environment, but that creates maintenance issues. I use one `values.yaml` file that has placeholders for the environment-specific values that get set at deploy time.

There are a few secret values that are needed in the pipeline. There is a `step` that pulls the secrets from the secret store and set them as pipeline variables, then you can use those to substitute the placeholders in the `values.yaml` file.

#### Preamble

The preamble is similar to the build pipeline. The main difference is this is never triggered by a commit, instead it is triggered by the build pipeline, which is added in the `resources` section.

```yaml
name: '1.3.$(Rev:r)-$(DeploySuffix)'

parameters:
- name: environmentOverrides
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

resources:
  pipelines:
  - pipeline: build           # a name for access the build pipeline in this one
    source: build_my-test-api # Must match the AzDO pipeline name
    trigger:
      branches:
        include:
          - main            # Only trigger a deploy from the main branch build
```

[trigger](https://learn.microsoft.com/en-us/azure/devops/pipelines/yaml-schema/trigger?view=azure-pipelines) and [pr](https://learn.microsoft.com/en-us/azure/devops/pipelines/yaml-schema/pr?view=azure-pipelines) are disabled for the deploy pipeline since we never want to run it when code changes.

[resources.pipelines.pipeline](https://learn.microsoft.com/en-us/azure/devops/pipelines/yaml-schema/resources-pipelines-pipeline?view=azure-pipelines) is how we trigger the deploy pipeline from the build pipeline. The `source` is the name you give the build pipeline when you creating it in AzDO. In the `trigger` section I limit running the deploy pipeline only when a `main` branch build is run.

There are other types of resources, which I'll cover in a later blog post.

#### The Work

Since the deployment yaml to each environment is identical, I use an `${{each}}` loop to deploy to each environment. For any differences between environments that can't be handled by simply using the `env` variable, I include a separate yaml file for each environment.

There's not too much to the deployment, and this sample is stubbed out. In general, a Helm deploy will have the following steps:

1. Get the secrets from the secret store to connect to K8s.
1. Connect to the K8s cluster.
1. Replace the placeholders in the `values.yaml` file with the environment-specific values. (Or you can use separate `values-<env>.yaml` files 🤮)
1. Deploy the Helm chart.

> There is a [Helm task](https://learn.microsoft.com/en-us/azure/devops/pipelines/tasks/reference/helm-deploy-v0?view=azure-pipelines) but I found that it didn't handle failures very well. If a deploy pipeline failed to deploy to K8s, you just get a timeout. To get better error handling, I wrote a PowerShell module, [K8sUtils](https://www.powershellgallery.com/packages/K8sUtils), that does a Helm install, but captures all the events, and logs from the deploy and fails on the first error. Before even if the deploy failed immediately in K8s, the Helm task would still wait until the timeout before returning. Using module has made life much easier in my current situation.

```yaml
stages:
- ${{ each env in parameters.environments }}: # create this stage for each environment
  - stage: deploy_${{ lower(env) }}           # stage names must be unique
    displayName: Deploy ${{ env }}

    variables:
      - name: envLower
        value: ${{ lower(env) }}

      - template: DevOps/variables/$(envLower)-environment.yml # What magic is this? See below.

    jobs:
    - job: deploy_${{ envLower }  }           # job names must be unique
      displayName: Deploy ${{env }} SC
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
          Install-Module -Name K8sUtils -Repository Loyal -Credential $cred -AllowClobber -Force -AllowPrerelease:$prerelease -PassThru | Select-Object Name, Version, PreRelease

          Get-Module K8sUtils | Select-Object Name, Version, PreRelease

          $skipRollbackOnError = '${{ parameters.skipRollbackOnError }}' -eq 'true'
          $verbose = '${{ parameters.verbose }}' -eq 'true'
          $selector = ('${{ parameters.skipDeploy }}' -eq 'true') ? '' : 'app=${{ parameters.releaseName }}'
          $dryRun = '${{ parameters.dryRun }}' -eq 'true'
          $timeoutSecs = ${{ parameters.timeoutMin }}*60
          $preHookTimeoutSecs = ${{ parameters.preHookTimeoutMin }}*60
          $preHookJobName = '${{ parameters.preHookJobName }}'

          $parms = [ordered]@{
            Chart = '${{ parameters.chart }}'
            ChartName = '${{ parameters.chartName }}'
            ChartVersion = '${{ parameters.chartVersion }}'
            DeploymentSelector = $selector
            DryRun = $dryRun
            Namespace = '${{ parameters.namespace }}'
            PodTimeoutSecs = $timeoutSecs
            PreHookJobName = $preHookJobName
            PreHookTimeoutSecs = $preHookTimeoutSec
            ReleaseName = '${{ parameters.releaseName }}'
            SkipRollbackOnError = $skipRollbackOnError
            ValueFile = '$(Agent.TempDirectory)/$(valueFileName)'
            Verbose = $verbose
            }


          "Calling Invoke-HelmUpgrade with:"
          $parms

          # fake out
          $deploy = Invoke-HelmUpgrade @parms

          $deploy | ConvertTo-Json -Depth 5 -EnumsAsStrings

          if (!$dryRun -and !$deploy.Running -and ($selector -or $preHookJobName)) {
            Write-Error "Deployment failed since not deploy.Running is false"
            exit 1
          }
        displayName: Deploy $(applicationDeployableName)
```

Notice in the variables section there is a `template` keyword. (I'll get more into templates in a later blog post.) In this case, I have a YAML file per environment and using a naming convention I can include the correct one for the each environment. The variables in these files are used to replace the placeholders in the `values.yaml` file avoiding the need for separate `values-<env>.yaml` files.

The replacement step uses a third-party task you may need to install in you AzDO organization. You may use another, or roll your own but using something like this is a good idea. The odd `./DevOps/values.yaml => $(Agent.TempDirectory)/$(valueFileName)` syntax tells it not to overwrite the original file. I had a problem in one pipeline that did multiple deploys using the same `values.yaml` file, and the second replacement step would do nothing since all the placeholders were already replaced (with the values I don't want in the second one!).

The `Show Helm Values` step is a debugging aid. Often we would have problems in a deployment and looking at the values file we could spot it (usually a YAML indenting issue). Alternatively, you could save the file as a pipeline artifact.

### 💁 Where to Store Secrets

This is specific to your environment. In my examples, the Helm chart `values.yaml` file uses K8s secrets to get the secrets into the container. Your app may make calls into a cloud key provider, etc., which has the issue of where to get the credentials to access the key provider.

K8s has providers that can create secrets from cloud key vaults which is a good solution. In that case you want to make sure only authorized users can view the values of those in K8s.

### Creating and Running the Pipelines

You should create your YAML on a feature branch and test it before merging it to the main branch. Chances are you will have to make several fixes to get a clean run and you don't want to be doing a bunch of PRs, etc. My process is

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

I hope this will help you get started building your own pipelines. This the way I've been doing pipelines at my last few jobs, and it has been working for us. In the next post I'll show how to create a reusable template repository so you can scale out your pipelines across many projects.

## Links

Docker documentation:

- [Build Context](https://docs.docker.com/build/concepts/context/)
- [.dockerignore](https://docs.docker.com/build/concepts/context/#dockerignore-files)

Azure DevOps documentation:

- [Run and Build Numbers (pipeline name)](https://learn.microsoft.com/en-us/azure/devops/pipelines/process/run-number?view=azure-devops)
- [Set an output variable for use in future stages](https://learn.microsoft.com/en-us/azure/devops/pipelines/process/set-variables-scripts?view=azure-devops&tabs=bash#set-an-output-variable-for-use-in-future-stages)
- [Conditions](https://learn.microsoft.com/en-us/azure/devops/pipelines/process/conditions?view=azure-devops&tabs=yaml%2Cstages)
- [Predefined Build Variables](https://learn.microsoft.com/en-us/azure/devops/pipelines/build/variables?view=azure-devops&tabs=yaml#build-variables-devops-services)
- [Predefined System Variables](https://learn.microsoft.com/en-us/azure/devops/pipelines/build/variables?view=azure-devops&tabs=yaml#system-variables-devops-services)
