---
title: Consuming Artifacts in Azure DevOps Pipelines
tags:
 - azdo
 - pipeline
 - artifact
excerpt: Consuming pipeline artifacts
cover: /assets/images/leaf12.png
comments: true
layout: article
key: 20250630
---
![image]({{ page.cover }}){: width="{{ site.imageWidth }}" }

This is the second blog that explores various ways to use artifacts in Azure DevOps pipelines. The [first blog](/2025/05/05/pipeline-artifacts.html) covered publishing pipeline artifacts, while this blog will focus on downloading them.

> I assume you have a basic understanding of Azure DevOps pipelines and the terminology. In an earlier blog there's a [brief lesson](/2024/08/10/typical-pipeline.html#folder-structure) on pipelines.

## Publishing for This Blog

For demonstrating downloading, the following snippet publishes two files. It is run in a loop setting `env` to `a`, then `b`

```yaml
- pwsh: |
    "this is from ${{ env }} at $((get-date).tostring("mm:ss.fff"))" > $(Agent.TempDirectory)/result.txt
    "this is from ${{ env }} at $((get-date).tostring("mm:ss.fff"))" > $(Agent.TempDirectory)/${{env}}_result.txt
    Write-Host "##vso[artifact.upload artifactname=${{env}}]$(Agent.TempDirectory)/${{env}}_result.txt"
    Write-Host "##vso[artifact.upload artifactname=${{env}}]$(Agent.TempDirectory)/result.txt"
```

The resulting artifacts will be as follows:

![Links for artifacts](/assets/images/artifacts/artifact-link-0.png)

## Downloading Artifacts from the Portal

To download an artifact from a pipeline to your machine, there are links on the pipeline's summary page. In the `Related` section, the `2 published` is a link to artifacts, as well as the `1 artifact` link in each job.

![Links for artifacts](/assets/images/artifacts/artifact-link-1.png)

Then, when you open a job, there is another link to the artifacts.

![Links within a job](/assets/images/artifacts/artifact-link-2.png)

You would think that the links would take you to the artifacts for the job, but they all take you to the list of all the artifacts for the pipeline. You then have to figure out which artifact you're after.

![List of artifacts](/assets/images/artifacts/artifact-list.png)

You can use the kebab menu (⋮) to download all the files in the artifact, or one specific file within the artifact.

## Downloading Artifacts from the CLI

The previous post has a [section](https://seekatar.github.io/2025/05/05/pipeline-artifacts.html#using-the-command-line-to-list-artifacts) that shows how to get artifacts from the CLI.

## Downloading Artifacts in a Pipeline

There are two ways to download pipeline artifacts from an Azure DevOps pipeline:

- Use the [DownloadPipelineArtifact](https://learn.microsoft.com/en-us/azure/devops/pipelines/tasks/reference/download-pipeline-artifact-v2?view=azure-pipelines) task.
- Use the [download](https://learn.microsoft.com/en-us/azure/devops/pipelines/yaml-schema/steps-download?view=azure-pipelines) keyword, which is a wrapper for `DownloadPipelineArtifact` as well as [DownloadBuildArtifacts](https://learn.microsoft.com/en-us/azure/devops/pipelines/tasks/reference/download-build-artifacts-v1) and [DownloadFileshareArtifacts](https://learn.microsoft.com/en-us/azure/devops/pipelines/tasks/reference/download-fileshare-artifacts-v1?view=azure-pipelines) task.

They both will download artifacts, but the latter is more generic, so I usually use `DownloadPipelineArtifact` to be explicit about what I'm doing.

### Using a Task

The [DownloadPipelineArtifact](https://learn.microsoft.com/en-us/azure/devops/pipelines/tasks/reference/download-pipeline-artifact-v2?view=azure-pipelines) task.

The simplest way to download all the artifacts is to add the task with no parameters.. It will download each artifact into a subfolder of `$(Pipeline.Workspace)`, which will be something like `/home/vsts/work/1`

```yaml
- task: DownloadPipelineArtifact@1
```

Given the artifacts published above, the files will be in a subfolder with the artifact name like this:

```text
/home/vsts/work/1/a/a_result.txt
/home/vsts/work/1/a/result.txt
/home/vsts/work/1/b/b_result.txt
/home/vsts/work/1/b/result.txt
```

To only download `a` into `$(Pipeline.Workspace)`

```yaml
- task: DownloadPipelineArtifact@2
  inputs:
    artifactName: a
```

The files will not be in a subfolder, but directly in `$(Pipeline.Workspace)`:

```text
/home/vsts/work/1/result.txt
/home/vsts/work/1/a_result.txt
```

And to put them into a specific folder, you can use the `downloadPath`:

```yaml
- task: DownloadPipelineArtifact@2
  inputs:
    artifactName: b
    targetPath: test
```

The files will be in a `test` folder:

```text
/home/vsts/work/1/s/test/b_result.txt
/home/vsts/work/1/s/test/result.txt
```

You can also filter the files to pull from the artifact using `itemPattern` using [pattern matching](https://learn.microsoft.com/en-us/azure/devops/pipelines/tasks/file-matching-patterns?view=azure-devops). Note that the path will include the artifact name, so you can use `**/pattern` or prefix with the name, as below.

```yaml
- task: DownloadPipelineArtifact@2
  inputs:
    artifactName: b
    targetPath: test
    itemPattern: b/result.*
```

Only the one file will be in a `test` folder:

```text
/home/vsts/work/1/s/test/result.txt
```

## Downloading Artifacts from a Different Pipeline

I've found that usually I'm in the same pipeline when I download an artifact, but you can also download artifacts from a different pipeline. In the yaml below, I trigger this pipeline from the one that created the artifacts (`test-artifact`), and then download `a` to the `test` folder. As you can see, there are many more parameters required in this case, and more optional ones not shown.

```yaml
resources:
 pipelines:
   - pipeline: test-artifact
     source: test-artifact
     branch: test-pipeline
     trigger: true

steps:
  - task: DownloadPipelineArtifact@2
    inputs:
      buildType: specific
      buildVersionToDownload: latest
      definition: 55 # pipelineId
      project: PipelineTest
      branchName: test-pipeline
      targetPath: test
      artifactName: a
```

Which results in the following files.

```text
/home/vsts/work/1/s/test/a_result.txt
/home/vsts/work/1/s/test/result.txt
```

## Summary

There are several scenarios where one stage publishes files that downstream ones consume. In this blog, I covered downloading them within a pipeline, as well as from a different pipeline.
