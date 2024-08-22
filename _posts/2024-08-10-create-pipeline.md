---
title: Creating a New Azure DevOps Pipeline
tags:
 - devops
 - yaml
 - pipeline
 - build
 - deploy
excerpt: Step-by-step instructions to create a new pipeline in Azure DevOps.
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

Here are the step-by-step instructions to create a new pipeline in Azure DevOps.

In the Pipelines section of Azure DevOps, click on the `New pipeline` button.

![New pipeline button](images/create-1.png)

Select `GitHub` as your code location.

![New pipeline button](images/create-2.png)

Select `All repositories` and filter on the one with your yaml.

![New pipeline button](images/create-3.png)

Select `Existing...`

![New pipeline button](images/create-4.png)

Choose your yaml file on your branch.

> Pro tip: If you're adding multiple pipelines after adding the first one, use the back button in the browser to get back to this location and avoid the steps above.

![New pipeline button](images/create-5.png)

`Save` the pipeline. It will take a minute and give it a default name.

![New pipeline button](images/create-6.png)

Use `Rename/move` to give it a better name, then click `Edit`.

![New pipeline button](images/create-7.png)

In the editor, click the kebab menu and `Validate`. You can correct errors here, or in your local editor, and push up the changes.

![New pipeline button](images/create-8.png)
