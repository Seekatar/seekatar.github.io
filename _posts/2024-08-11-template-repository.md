---
title: Using a Template Repository for Azure DevOps Pipelines
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

This is the second in a series of blog posts about creating reusable Azure DevOps YAML pipelines across many projects. In these posts, I'll build a containerized .NET API with unit tests and do deployments to multiple environments (faked-out). This first post creates pipelines as one-offs without reusing YAML. The second post will leverage templates to create a reusable library of pipeline steps. The third post will take templates to the next level by creating a dynamic pipeline driven by feature flags.

1. [Typical Kubernetes Build and Deploy Azure DevOps Pipelines](/2024/08/10/typical-pipeline.html)
1. Moving Azure DevOps Pipelines Logic to a Template Repository (this post)
1. [Creating a Dynamic Azure DevOps Pipeline](/2024/08/21/build-pipeline.html)
1. [Azure DevOps Pipeline Tips and Tricks](/2024/08/22/azdo-tat.html)

> 💁 I assume you have read the previous blog and are familiar with the basic application lifecycle concepts for containerized applications.

The YAML, sample source code, and pipelines are all in [this](https://dev.azure.com/MrSeekatar/SeekatarBlog/_git/TypicalPipeline) AzDO Project.

## The Problem

Now that I have a nice YAML CI/CD set of pipelines, I want to reuse then across my organization. Many of my applications are similar, and they all deploy to the same environment

## The Solution

In this post, I'll take the build and deploy yaml from the previous post, and move chunks of YAML (templates) into a separate repository. Then I can use those chunks in pipelines across my organization. By having one central location, I can make changes and fixes to the shared YAML and have all the pipelines that use it updated.

> 💁 Brief Lesson on Templates
>
> [Templates](https://learn.microsoft.com/en-us/azure/devops/pipelines/process/templates?view=azure-devops&pivots=templates-includes) are chunks of YAML that can be included in other YAML files, similar to `#include` in C++. In this post I'll use the term `template` to refer to `Includes Templates` (I'll cover `Extends Templates` in the next post).
>
> Each template contains one type of AzDO object, such as a `stages`, `jobs`, `steps`, or `variables`. One of those keywords will be in each file, and then it can only be used under the same keyword. E.g if the template has `steps` it can only go under `steps` in the calling YAML. Templates can have [parameters](https://learn.microsoft.com/en-us/azure/devops/pipelines/process/template-parameters?view=azure-devops), so you can make them as flexible as possible.
>

I used a template in the first post to pull in the variables for the pipeline. In that case the template was in the same repo as the caller. In this post the templates will be in a separate repo.

### The Shared Repository

For the templates, I create an `azdo-templates` repository with the following structure:

```plaintext
.
├── jobs
├── stages
├── steps
└── variables
```

As the folder names suggest, each one will contain only templates of that type. To use templates from this repository, I must include the repository in the `resources` section of the calling pipeline, like the following:

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
1. Test the changes in a pipeline by updating another pipeline to use the new branch
1. Merge the branch to `main`
1. If the changes are not breaking, merge `main` to the highest numbered `releases` branch, e.g. `releases/v1.0`
1. If the changes are breaking, branch off `main` with a new `releases` branch, e.g. `releases/v1.1`

This allows users of the template to get fixes or new functionality automatically. But if there are breaking changes, they can choose when to opt into the new release. (I initially used tags, but that got messy with git.)

### Splitting Out the Templates



## Links

Azure DevOps documentation:

- [Templates](https://learn.microsoft.com/en-us/azure/devops/pipelines/process/templates?view=azure-devops&pivots=templates-includes)
- [Template Parameters](https://learn.microsoft.com/en-us/azure/devops/pipelines/process/template-parameters?view=azure-devops)
