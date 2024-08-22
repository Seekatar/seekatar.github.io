---
title: Using a Template Repository for Azure DevOps Pipelines
tags:
 - devops
 - yaml
 - pipeline
 - featureflags
excerpt: Moving pipeline logic to a template repository, with feature flags
cover: /assets/images/leaf-1408533.jpg
comments: true
layout: article
key: 20240811
---

![image]({{ page.cover }}){: width="{{ site.imageWidth }}" }

This is the first in a series of blog posts about creating a set of Azure DevOps YAML pipelines to standardize across many projects.

1. Typical Kubernetes Build and Deploy Azure DevOps Pipelines
1. Moving Azure DevOps Pipelines Logic to a Template Repository
1. Creating a Dynamic Azure DevOps Pipeline
1. Azure DevOps Pipeline Tips, Tricks, Gotchas, and Headaches

## The Problem

From management:

> We are outsourcing work overseas and need to standardize on branching, builds, and deployments for our 100+ deployables.

That sounds pretty scary, but we already had most of our CI/CD in Azure DevOps as YAML and had a bunch YAML in a shared repo. As a DevOps developer that sounded tedious, but not complex (Probably a matter of writing a few scripts.).

We knew that even if we wrote a script to tweak all our pipelines' YAML in all their repos, there would be changes. Having the YAML in one shared repository was the most logical solution. We already had a shared repository with many helpers that were as small as a task to connect to a NuGet feed, or entire stages for building or deploying. Now we needed to move up a level and encapsulate the entire build and deploy pipelines making the apps' YAML files as small as possible.

One size fit-all rarely works, but we can make a template that handles nearly all the cases, and expose variables that can be used to configure the behavior or the pipeline, without adding code to the pipeline itself. Using that method we can change or add new features to the pipelines without having to modify any app's YAML. This is the topic of this blog.


## Links

Azure DevOps documentation:

- [Set an output variable for use in future stages](https://learn.microsoft.com/en-us/azure/devops/pipelines/process/set-variables-scripts?view=azure-devops&tabs=bash#set-an-output-variable-for-use-in-future-stages)
- [Conditions](https://learn.microsoft.com/en-us/azure/devops/pipelines/process/conditions?view=azure-devops&tabs=yaml%2Cstages)
- [Predefined Build Variables](https://learn.microsoft.com/en-us/azure/devops/pipelines/build/variables?view=azure-devops&tabs=yaml#build-variables-devops-services)
- [Predefined System Variables](https://learn.microsoft.com/en-us/azure/devops/pipelines/build/variables?view=azure-devops&tabs=yaml#system-variables-devops-services)
