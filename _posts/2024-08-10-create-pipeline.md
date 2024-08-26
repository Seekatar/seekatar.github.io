---
title: Creating a New Azure DevOps Pipeline
tags:
 - devops
 - YAML
 - pipeline
 - create
 - azureDevOps
excerpt: Step-by-step instructions to create a new pipeline in Azure DevOps.
cover: /assets/images/leaf5.webp
comments: true
layout: article
key: 20240810
---

![image]({{ page.cover }}){: width="{{ site.imageWidth }}" }

> This a little helper blog to show how you create a YAML pipeline in Azure DevOps. I reference this in my blog series about YAML pipelines.

Here are the step-by-step instructions to create a new pipeline in Azure DevOps.

In the Pipelines section of Azure DevOps, click on the `New pipeline` button.

![New pipeline button](/assets/images/createPipeline/create-1.png)

Select the location of your YAML.

![New pipeline button](/assets/images/createPipeline/create-2.png)

Select the one with your YAML. You may have to click `All Repositories` to see it.

![New pipeline button](/assets/images/createPipeline/create-3.png)

Select `Existing...`

![New pipeline button](/assets/images/createPipeline/create-4.png)

Choose your YAML file on your branch.

> Pro tip: If you're adding multiple pipelines after adding the first one, use the back button in the browser to get back to this location and avoid the steps above.

![New pipeline button](/assets/images/createPipeline/create-5.png)

`Save` the pipeline. It will take a minute and give it a default name of the AzDO Project.

![New pipeline button](/assets/images/createPipeline/create-6.png)

Use `Rename/move` to give it a better name, then click `Edit`.

![New pipeline button](/assets/images/createPipeline/create-7.png)

In the editor, click the kebab menu and `Validate`. You can correct errors here, or in your local editor, and push up the changes.

![New pipeline button](/assets/images/createPipeline/create-8.png)

After your pipeline validates you can `Run` it!
