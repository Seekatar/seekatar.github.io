---
title: ONBUILD Can Keep Secrets Out of Docker Images
tags:
 - docker
 - dotnet
 - nuget
 - onbuild
 - security
 - buildkit
excerpt: Avoid baking secrets into base images by using Docker's ONBUILD instruction combined with BuildKit secrets.
cover: /assets/images/leaf1.jpg
comments: true
layout: article
key: 20260211
---

![image]({{ page.cover }}){: width="{{ site.imageWidth }}" }

## The Problem

We have custom .NET SDK base image, that sets up the build environment for all our applications. In the Dockerfile, we create a `NuGet.config` file for accessing our private NuGet repository. Originally we baked in a Personal Access Token (PAT), and used a multistage Dockerfile to avoid leaking the PAT. This is fine, except PATs expire, and then stuff breaks.

To solve that we decided to use Managed Identities in the Azure DevOps pipeline so we never have to worry about expiring credentials. The problem with that is that the NuGet credentials aren't known when the base image is built. What we need is a way to have common code in the base Docker file, but pass in the credentials at build time. The Dockerfile ONBUILD instruction to the rescue!

```dockerfile
ARG sdkVersion=9.0

FROM mcr.microsoft.com/dotnet/sdk:${sdkVersion} AS build
ARG nugetPassword
ARG nugetUsername=IgnoredWhenUsingPAT
ARG certPassword

RUN apt update -y && apt upgrade -y

WORKDIR /app

RUN dotnet nuget add source "https://example.pkgs.visualstudio.com/_packaging/MyNuget/nuget/v3/index.json" \
                -n MyNuget -u ${nugetUsername} \
                -p ${nugetPassword} \
                --store-password-in-clear-text

# ... certificate generation, multi-stage copy, etc.

FROM mcr.microsoft.com/dotnet/sdk:${sdkVersion} AS final
COPY --from=build /app/cert.pfx /app/cert.pfx
COPY --from=build /root/.nuget/NuGet/NuGet.Config /root/.nuget/NuGet/NuGet.Config

WORKDIR /
```

And the build command would be something like:

```bash
docker build --build-arg nugetPassword=$NUGET_PAT -t my-sdk:9.0 .
```

This works, but there's a security problem: `ARG` values are baked into the image layer metadata. Anyone who can pull the image from the registry can run `docker history` and see the password in plain text.

```bash
$ docker history my-sdk:9.0
IMAGE          CREATED          CREATED BY                                      SIZE
...
<missing>      2 minutes ago    RUN ... -p MY_SECRET_PAT --store-password...    1.2kB
```

That's the NuGet PAT, right there in the layer history. Not great.

On top of that, the `NuGet.Config` file containing the password is copied into the `final` stage, so the password is also sitting in a file inside the published image.

> You may think of using `--mount=type=secret` but

## Using ONBUILD

Docker's [`ONBUILD`](https://docs.docker.com/reference/dockerfile/#onbuild) instruction allows you to add commands to a derived image when it is built. It's like putting a macro in the base image that is injected into the Dockerfile that uses this image.

Here's a typical example of using `ONBUILD`. We'll create a base image with all the tools to "compile" our app. In this case it's just `cowsay`. The base image installs it, and has a "compile.sh" script that runs it.

```dockerfile
```

The `ONBUILD` statements will copy the source code into the new image, do `ls`, then "compile" the code.

```dockerfile
```


By combining `ONBUILD` with `--mount=type=secret`, we get the best of both worlds. Here's the updated Dockerfile:

```dockerfile
ARG sdkVersion=9.0

FROM mcr.microsoft.com/dotnet/sdk:${sdkVersion} AS build
ARG certPassword

RUN apt update -y && apt upgrade -y

WORKDIR /app

# certificate generation
RUN openssl genrsa -des3 -passout pass:${certPassword} -out server.key 2048 && \
    openssl rsa -passin pass:${certPassword} -in server.key -out server.key && \
    openssl req -sha256 -new -key server.key -out server.csr -subj '/CN=my-service' && \
    openssl x509 -req -sha256 -days 3650 -in server.csr -signkey server.key -out server.crt && \
    openssl pkcs12 -export -out cert.pfx -inkey server.key -in server.crt -passout pass:${certPassword}

FROM mcr.microsoft.com/dotnet/sdk:${sdkVersion} AS final

COPY --from=build /app/cert.pfx /app/cert.pfx
COPY --from=build /root/.nuget/NuGet/NuGet.Config /root/.nuget/NuGet/NuGet.Config

WORKDIR /

ONBUILD RUN --mount=type=secret,id=nugetPassword,env=nugetPassword \
    dotnet nuget add source "https://example.pkgs.visualstudio.com/_packaging/MyNuget/nuget/v3/index.json" \
                -n MyNuget \
                -u az \
                -p $nugetPassword \
                --store-password-in-clear-text
```

Notice there is no `ARG nugetPassword` anywhere. The `ONBUILD` at the end means that `RUN --mount=type=secret` instruction is _stored_ but not _executed_ when building this base image. The base image is clean.

## What Happens Downstream

When a service Dockerfile does `FROM myregistry.azurecr.io/my-sdk:9.0`, Docker sees the `ONBUILD` trigger and runs the NuGet source configuration as the first step. The downstream build command passes the secret:

```bash
docker build --secret id=nugetPassword,env=NUGET_PAT -t my-service .
```

The flow is:

1. Docker processes the `FROM my-sdk:9.0` line
2. The `ONBUILD RUN --mount=type=secret,...` trigger fires
3. BuildKit mounts the `nugetPassword` secret as an environment variable for just that `RUN` step
4. `dotnet nuget add source` configures the private feed
5. The secret is never persisted in any layer

The NuGet.Config _does_ end up in the downstream build image with the password, but that's fine because service Dockerfiles use multi-stage builds -- the build stage with NuGet.Config is discarded, and only the final runtime stage (based on `aspnet`, not `sdk`) is published.

## Summary

| | `ARG` approach | `ONBUILD` + `--mount=type=secret` |
|---|---|---|
| Password in base image history | Yes | No |
| Password in base image files | Yes (NuGet.Config) | No |
| Password in downstream build layer | Yes | No (ephemeral mount) |
| Downstream must pass credentials | No (baked in) | Yes (via `--secret`) |

The combination of `ONBUILD` and BuildKit secrets is a clean solution for base images that need to defer credential configuration to their consumers. The base image stays secret-free, and each downstream build provides its own credentials ephemerally.

## Links

* [Dockerfile reference: ONBUILD](https://docs.docker.com/reference/dockerfile/#onbuild)
* [Docker BuildKit: Build secrets](https://docs.docker.com/build/building/secrets/)
* [Docker BuildKit: Multi-stage builds](https://docs.docker.com/build/building/multi-stage/)
