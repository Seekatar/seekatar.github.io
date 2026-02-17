---
title: ONBUILD Can Keep Secrets Out of Docker Images
tags:
 - docker
 - dotnet
 - nuget
 - onbuild
 - security
 - buildkit
excerpt: Avoid baking secrets into base images by using Docker's ONBUILD instruction.
cover: /assets/images/docker-1.png
comments: true
layout: article
key: 20260211
---

![image]({{ page.cover }}){: width="{{ site.imageWidth }}" }

## Introduction

In this post I'll share how I used Docker's `ONBUILD` instruction to avoid baking in a secret and use Managed Identities instead.

## The Problem

I have a custom .NET SDK base image that sets up the build environment for many applications to keep things DRY and standardized. In the `Dockerfile` of the base image, I create a `NuGet.config` file for accessing a private NuGet repository. Originally, I baked in a Personal Access Token (PAT), and used a multistage Dockerfile to avoid leaking it. That was fine, except PATs expire, and then stuff breaks.

To solve that, I decided to use Managed Identities in Azure DevOps pipelines so I never have to worry about expiring credentials. The problem with that is that the NuGet credentials for the Managed Identity aren't known when the base image is built. What I needed was a way to have common code in the base `Dockerfile`, but pass in the credentials at build time. The Dockerfile `ONBUILD` instruction solved that problem.

Here's a simplified version of the original `Dockerfile` (this sample will work, even with the dummy source URL.)

```dockerfile
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
ARG nugetPassword

RUN echo Other setup for build

RUN dotnet nuget add source "https://..." \
                -n MyNuget -u ignoredWhenUsingPAT --store-password-in-clear-text \
                -p ${nugetPassword}
```

To build the image with a super secret password:

```bash
docker build -t base -f ./Dockerfile-base --build-arg nugetPassword=Monkey123! .
```

That works, but there's a security problem: `ARG` values are baked into the image layer metadata. Anyone who can pull the image from the registry can run `docker history` and see the password in plain text.

```text
> docker history base
IMAGE          CREATED         CREATED BY                                      SIZE      COMMENT
b6437fdd4e05   3 seconds ago   RUN |1 nugetPassword=Monkey123! /bin/sh -c d…   3.87kB    buildkit.dockerfile.v0
<missing>      3 seconds ago   ARG nugetPassword=Monkey123!                    0B        buildkit.dockerfile.v0
```

There's the NuGet PAT, right there in the layer history. For me it wasn't a huge deal since you have to have access to pull the image to see it, and you'd probably have access to the NuGet feed anyway, but it'd probably be flagged in a security audit.

I got around that by using a second stage and copying the `NuGet.Config` from the first stage. That way the password didn't show up in the history, but it is still in the `NuGet.Config` file, so someone could shell into the image and read it.

## Using ONBUILD

Before diving into the specific solution, here's a contrived example demonstrating how `ONBUILD` works.

Docker's [`ONBUILD`](https://docs.docker.com/reference/dockerfile/#onbuild) instruction allows you to put instructions in a base image that get added to a derived image when it is built. It's like putting macros in the base image that are injected at the top of the derived image's `Dockerfile`.

Here's my example of using `ONBUILD` for compiling an app. I'll create a base image with all the tools to "compile" the app. In this case it's just `cowsay`. The base image installs it and creates a `compile.sh` script that runs it.

```dockerfile
FROM ubuntu AS base

WORKDIR /app

RUN echo 'echo ">>> Compiling..."\ncat ./cowsay.txt | cowsay\necho "<<< All done!"' > compile.sh . \
    chmod +x compile.sh

RUN apt-get update && apt-get install -y cowsay && rm -rf /var/lib/apt/lists/*
ENV PATH="${PATH}:/usr/games"

ONBUILD WORKDIR /app
ONBUILD COPY ./cowsay.txt .
ONBUILD RUN ls -la
ONBUILD RUN ./compile.sh
```

When it is built, notice that there are no `ONBUILD` instructions in the log or history:

```bash
> docker build -f ./Dockerfile-base -t base-cowsay .
...
 => => transferring context: 110B
 => [2/5] WORKDIR /app
 => [3/5] COPY compile.sh .
 => [4/5] RUN chmod +x compile.sh
 => [5/5] RUN apt-get update && apt-get install -y cowsay && rm -rf /var/lib/apt/lists/*
 => exporting to image
 ...
 ```

```bash
> docker history base-cowsay
IMAGE          CREATED          CREATED BY                                      SIZE      COMMENT
6eac5ad9e27e   50 minutes ago   ENV PATH=/usr/local/sbin:/usr/local/bin:/usr…   0B        buildkit.dockerfile.v0
<missing>      50 minutes ago   RUN /bin/sh -c apt-get update && apt-get ins…   52.2MB    buildkit.dockerfile.v0
<missing>      50 minutes ago   RUN /bin/sh -c chmod +x compile.sh # buildkit   73B       buildkit.dockerfile.v0
<missing>      50 minutes ago   COPY compile.sh . # buildkit                    73B       buildkit.dockerfile.v0
```

The derived Dockerfile looks like this:

```dockerfile
FROM base-cowsay

RUN echo "Derived image build complete"
```

When it is built, we'll see all the `ONBUILD` instructions executed as part of the build. It "compiles" cowsay.txt that was copied via the base image's `ONBUILD COPY ./cowsay.txt .` instruction:

```text
 => [1/2] FROM docker.io/library/base-cowsay:latest
 => [internal] load build context
 => => transferring context: 97B
 => [2/6] ONBUILD WORKDIR /app
 => [3/6] ONBUILD COPY ./cowsay.txt .
 => [4/6] ONBUILD RUN ls -la
 => [5/6] ONBUILD RUN ./compile.sh
 => [6/6] RUN echo "Derived image build complete"
 => exporting to image
```

Adding `--progress plain` to the build command shows the "compiler" output:

```text
#9 [5/6] ONBUILD RUN ./compile.sh
#9 0.342 >>> Compiling...
#9 0.356  ______________________________________
#9 0.356 / ONBUILD instructions executed during \
#9 0.356 \ build of derived image               /
#9 0.356  --------------------------------------
#9 0.356         \   ^__^
#9 0.356          \  (oo)\_______
#9 0.356             (__)\       )\/\
#9 0.356                 ||----w |
#9 0.356                 ||     ||
#9 0.357 <<< All done!
```

The history shows the `ONBUILD` instructions as if they were part of the derived image (in reverse order):

```text
> docker history derived-cowsay
IMAGE          CREATED              CREATED BY                                      SIZE      COMMENT
5b4167870dab   About a minute ago   RUN /bin/sh -c echo "Derived image build com…   0B        buildkit.dockerfile.v0
<missing>      About a minute ago   RUN /bin/sh -c ./compile.sh # buildkit          0B        buildkit.dockerfile.v0
<missing>      About a minute ago   RUN /bin/sh -c ls -la # buildkit                0B        buildkit.dockerfile.v0
<missing>      About a minute ago   COPY ./cowsay.txt . # buildkit                  60B       buildkit.dockerfile.v0
<missing>      About a minute ago   WORKDIR /app                                    0B        buildkit.dockerfile.v0
```

## Combining ONBUILD with Build Secrets

By using `ONBUILD`, I can defer getting the secret until build time. Here's the updated base Dockerfile with the `nuget add` now in an `ONBUILD` instruction, and no `ARG` instruction:

```dockerfile
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build

RUN echo Other setup for build

ONBUILD RUN --mount=type=secret,id=nugetPassword,env=nugetPassword \
        dotnet nuget add source "https://..." \
                -n MyNuget -u ignoredWhenUsingPAT --store-password-in-clear-text \
                -p ${nugetPassword}
```

The base image now only has one layer.

```bash
> docker history base-onbuild
IMAGE          CREATED         CREATED BY                                      SIZE      COMMENT
df2ae0933928   6 seconds ago   RUN /bin/sh -c echo "Other setup for build"    0B        buildkit.dockerfile.v0
```

The only change required to the derived `Dockerfile` is to change the `FROM` line to use `base-onbuild`. To build it, instead of using `ARG` to pass the secret, I used the `--mount=type=secret` parameter to get the `nugetPassword` passed in at build time:

```bash
export NUGET_PAT=Monkey123!
docker build -f ./Dockerfile-onbuild -t onbuild --secret id=nugetPassword,env=NUGET_PAT .
```

> Using `--secret` is a topic for another post, but it is the preferred way to pass secrets into builds. See the links below for more info.

If you want to verify that the secret is set, you can add this line in the first (build) stage of the derived Dockerfile:

```dockerfile
RUN cat /root/.nuget/NuGet/NuGet.Config
```

As a final note, in my Azure DevOps pipeline, setting the `NUGET_PAT` environment variable before the [Docker@2](https://learn.microsoft.com/en-us/azure/devops/pipelines/tasks/reference/docker-v2?view=azure-pipelines&tabs=yaml) task did not work. Instead, I used a temporary file and `--secret id=nugetPassword,src=$(Agent.TempDirectory)/nuget-password.txt`

## Summary

In this post, I shared how to use Docker's `ONBUILD` instruction to keep secrets out of base images. This allows you to have common build logic in the base image, but defer getting secrets until build time. For my particular scenario, it allowed me to use Managed Identities in Azure DevOps pipelines without baking a PAT into the base image.

## Links

* [Dockerfile reference: ONBUILD](https://docs.docker.com/reference/dockerfile/#onbuild)
* [Docker Build: Build secrets](https://docs.docker.com/build/building/secrets/)
* [Docker Build: Multi-stage builds](https://docs.docker.com/build/building/multi-stage/)
* [How to use Dockerfile ONBUILD to run triggers on downstream builds](https://www.howtogeek.com/devops/how-to-use-dockerfile-onbuild-to-run-triggers-on-downstream-builds/) - James Walker, HowToGeek
