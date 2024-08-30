---
title: Moving Azure DevOps Deploy Pipeline Logic to a Template Repository
tags:
 - devops
 - yaml
 - pipeline
 - template
excerpt: Moving deploy logic to a template repository
cover: /assets/images/leaf6.webp
comments: true
layout: article
key: 20240811
---

![image]({{ page.cover }}){: width="{{ site.imageWidth }}" }

This is the third in a series of blog posts about creating reusable Azure DevOps YAML pipelines across many projects. In these posts, I'll build a containerized .NET API with unit tests and deploys to multiple environments (faked-out). This first post creates pipelines as one-offs without reusing YAML. The second and third posts will leverage templates to create a reusable library of pipeline steps. The fourth post will take templates to the next level by creating a dynamic pipeline driven by feature flags.

1. [Typical Kubernetes Build and Deploy Azure DevOps Pipelines](/2024/08/10/typical-pipeline.html)
1. [Moving Azure DevOps Build Pipeline Logic to a Template Repository](/2024/08/11/build-template-repository.html)
1. Moving Azure DevOps Deploy Pipeline Logic to a Template Repository (this post)
1. [Creating a Dynamic Azure DevOps Pipeline](/2024/08/21/build-pipeline.html)
1. [Azure DevOps Pipeline Tips and Tricks](/2024/08/22/azdo-tat.html)

> 💁 I assume you have read the previous blog and are familiar with the basic application lifecycle concepts for containerized applications.

The YAML, sample source code, and pipelines are all in [this](https://dev.azure.com/MrSeekatar/SeekatarBlog/_git/TypicalPipeline) AzDO Project.

## The Problem


## The Solution

In this post, I'll take the deploy yaml from a previous post, and move chunks of YAML (templates) into a separate repository. Then I can use those chunks in pipelines across my organization. By having one central location, I can make changes and fixes to the shared YAML and have all the pipelines that use it updated.

### Creating the Deploy Templates

The deploy pipeline for the example is mainly stubbed out since deployment will be unique to your situation. Although unique to your situation, it will probably be the same for many of your applications. In this example, I'll show how you can create a template that will deploy to Kubernetes using Helm. The steps to do so are as follows:

1. Get the K8s credentials
1. Log into K8s
1. Replace environment-specific values in the Helm values.yaml file
1. Call a script to use K8sUtils to deploy to Helm

That list of tasks should be what any K8s deploy runs. Let's see how to make that a `template`. We could make the template a stage, job, or steps. I'll make it steps since that way it can be used in any job. I can always wrap it in a job template if I need to.

The original pipeline had a dry run parameter, so we'll need that. Then since this template will go under `steps` in the calling pipeline, we'll add that to the template.


Now we can run the build pipeline just as before. The interesting part to this exercise it that the expanded YAML for the templated and non-templated pipelines are the same! We just made the pipeline more reusable. Here's the view of the templated pipeline, and you see all of the steps are the same as the original pipeline.

![Comparing two build steps](/assets/images/devOpsBlogs/compare-builds.png)

## Links

Azure DevOps documentation:

- [Templates](https://learn.microsoft.com/en-us/azure/devops/pipelines/process/templates?view=azure-devops&pivots=templates-includes)
- [Template Parameters](https://learn.microsoft.com/en-us/azure/devops/pipelines/process/template-parameters?view=azure-devops)
