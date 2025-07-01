---
title: Publishing Artifacts in Azure DevOps Pipelines
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

This is the second blog that explores various ways to use artifacts in Azure DevOps pipelines. The [first blog](2025/05/05/pipeline-artifacts.html) covered publishing pipeline artifacts, while this blog will focus on downloading them.

> I assume you have a basic understanding of Azure DevOps pipelines and the terminology. In an earlier blog there's a [brief lesson](/2024/08/10/typical-pipeline.html#folder-structure) on pipelines.

## Downloading Artifacts from the Portal

If you want to download an artifact from a pipeline to your machine, there are several links on the pipeline's summary page. In the `Related` section, the `4 published` is a link to artifacts, as well as the `2 artifacts` link in each job.

![Links for artifacts](/assets/images/artifacts/artifact-link-1.png)

Then when you open a job, there is another link to the artifacts.

![Links within a job](/assets/images/artifacts/artifact-link-2.png)

You would think that the links would take you to the artifacts for the job, but they all take you to the list of all the artifacts for the pipeline. You then have to figure out which artifact you're after.

![List of artifacts](/assets/images/artifacts/artifact-list.png)

You can use the kebab menu (⋮) to download all the files in the artifact, or one specific file within the artifact.

## Downloading Artifacts from the CLI

The previous post has a [section](https://seekatar.github.io/2025/05/05/pipeline-artifacts.html#using-the-command-line-to-list-artifacts) that shows how to get artifacts from the CLI.

## Downloading Artifacts in a Pipeline

There are two ways to download artifacts from an Azure DevOps pipeline:

- Use the [DownloadPipelineArtifact](https://learn.microsoft.com/en-us/azure/devops/pipelines/tasks/reference/download-pipeline-artifact-v2?view=azure-pipelines) task.
- Use the [download](https://learn.microsoft.com/en-us/azure/devops/pipelines/yaml-schema/steps-download?view=azure-pipelines) keyword in the YAML pipeline, which is a wrapper for `DownloadPipelineArtifact` as well as [DownloadBuildArtifacts](https://learn.microsoft.com/en-us/azure/devops/pipelines/tasks/reference/download-build-artifacts-v1) and [DownloadFileshareArtifacts](https://learn.microsoft.com/en-us/azure/devops/pipelines/tasks/reference/download-fileshare-artifacts-v1?view=azure-pipelines) task. The latter two are not discussed in this blog.

They both will download artifacts, but the latter is more generic, so I usually use `DownloadPipelineArtifact` to be explicit about what I'm doing.

### Using a Task

The [DownloadPipelineArtifact](https://learn.microsoft.com/en-us/azure/devops/pipelines/tasks/reference/download-pipeline-artifact-v2?view=azure-pipelines) task.

```yaml
- task: DownloadPipelineArtifact@1
  inputs:
    targetPath: '$(Agent.TempDirectory)/result_pub.txt'
    artifact: 'publish_a_pub_1'
```
