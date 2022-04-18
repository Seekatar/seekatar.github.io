---
# author: seekatar
title: Running .NET Unit tests in Docker
tags:
 - docker
 - dotnet
 - unittest
 - xunit
excerpt: Run unit tests in Docker and extract results
cover: /assets/images/leaf1.jpg
comments: true
layout: article
key: apr-18-2022
---

![image]({{ page.cover }}){: width="{{ site.imageWidth }}" }

## Adding Unit Test to Docker

If you're going to build and publish a Docker image, it makes sense to run your tests in a container. If you run the test outside of the container, you _really_ aren't testing the binary that you'll be deploying. I know, I know, it _should_ be the same, but is your build environment on the build box exactly the same as in the container? Does it have all the same versions of libraries, etc? Probably not.

Also, if you test outside the container, you're building twice, once on the build box for testing, and once in the container, slowing down your build process.

To do testing, I use a multi-stage `Dockerfile` that has build, test, and run stages. It's pretty straightforward as a Dockerfile goes. Here's a typical one.

```dockerfile
FROM mcr.microsoft.com/dotnet/runtime:6.0 AS base
WORKDIR /app

FROM mcr.microsoft.com/dotnet/sdk:6.0 AS build
WORKDIR /src
COPY ["dotnet-console/dotnet-console.csproj", "./dotnet-console/dotnet-console.csproj"]
COPY ["unit/unit.csproj", "./unit/unit.csproj"]
COPY ["dotnet-console.sln", "."]
RUN dotnet restore

COPY . .
RUN dotnet publish "./dotnet-console/dotnet-console.csproj" -c Release -o /app/publish

FROM build AS test
WORKDIR /src
LABEL unittestlayer=true
WORKDIR /src/unit
RUN dotnet test --logger "trx;LogFileName=UnitTests.trx" --results-directory /out/testresults /p:CollectCoverage=true /p:CoverletOutputFormat=cobertura /p:CoverletOutput=/out/testresults/coverage/

FROM base AS final
COPY --from=build /app/publish .
ENTRYPOINT ["dotnet", "dotnet-console.dll"]
```

You can see there's a build stage that published the dotnet app, a test stage to test the app, and a final stage that is used at runtime.

## Getting the Test Output Locally

To get the test results locally, you can watch the output from the build, or after it completes, copy the output from the container.

```powershell
$unittestslayerid=$(docker images --filter "label=unittestlayer=true" -q | Select-Object -first 1)
if ($unittestslayerid) {
    docker create --name unittestcontainer $unittestslayerid
    Remove-Item ./testresults/* -Recurse -Force -ErrorAction Ignore
    docker cp unittestcontainer:/out/testresults .
    docker stop unittestcontainer
    docker rm unittestcontainer
    docker rmi $unittestslayerid

    if (Test-Path ./testresults/UnitTests.trx) {
        $test = [xml](Get-Content ./testresults/UnitTests.trx -Raw)
        $finish = [DateTime]::Parse($test.TestRun.Times.finish)

        $test.TestRun.ResultSummary.Counters.passed
        Write-Output "Test finished at $($finish.ToString("HH:mm:ss"))"
        Write-Output "  Outcome is: $($test.TestRun.ResultSummary.outcome)"
        Write-Output "  Success is $($test.TestRun.ResultSummary.Counters.passed)/$($test.TestRun.ResultSummary.Counters.total)"
    } else {
        Write-Warning "No output found in ./testresults/testresults/UnitTests.trx"
    }
} else {
    Write-Warning "No image found with label unittestlayer=true"
}
```

## Getting the Test Output in Azure DevOps

Like getting the results locally, you pull the content from the container, the use the publish tasks to get them into DevOps for you.

```yaml
- script: |
    export unittestslayerid=$(docker images --filter "label=unittestlayer=true" -q)
    docker create --name unittestcontainer $unittestslayerid
    docker cp unittestcontainer:/out/testresults ./testresults
    docker stop unittestcontainer
    docker rm unittestcontainer
  displayName: Run unit tests
  continueOnError: false

- task: PublishTestResults@2
  displayName: 'Publish Test Results'
  inputs:
    testRunner: VSTest
    testResultsFiles: '**/dockerunittestspiketestresults.xml'
    searchFolder: '$(System.DefaultWorkingDirectory)/testresults'
    publishRunAttachments: true
    failTaskOnFailedTests: true

- task: PublishCodeCoverageResults@1
  inputs:
    codeCoverageTool: 'cobertura'
    summaryFileLocation: '$(System.DefaultWorkingDirectory)/testresults/coverage/coverage.cobertura.xml'
    reportDirectory: '$(System.DefaultWorkingDirectory)/testresults/coverage/reports'
  displayName: 'Publish coverage reports'
```

Yay! Test and code coverage output. [Here's](https://dev.azure.com/MrSeekatar/PipelineTest/_build/results?buildId=657&view=results) the build pipeline for this run.

![test-results](/assets/images/test-success.png)

## The Problem with BuildKit

This is all well and good, unless you have BuildKit enabled, then the test stage it not run at all!

> Note as of this writing Azure DevOps does _not_ have BuildKit enabled by default, and the above Dockerfile works fine (see [here](https://docs.microsoft.com/en-us/azure/devops/pipelines/ecosystems/containers/build-image?view=azure-devops#how-do-i-set-the-buildkit-variable-for-my-docker-builds)). If you run this locally with BuildKit enabled (the default for Docker Desktop nowadays), this is a problem for you and you may continue reading, otherwise, you're excused.

```text
[+] Building (18/18) FINISHED
 => [internal] load build definition from Dockerfile-3stage
 => => transferring dockerfile: 996B
 => [internal] load .dockerignore
 => => transferring context: 382B
 => [internal] load metadata for mcr.microsoft.com/dotnet/sdk:6.0
 => [internal] load metadata for mcr.microsoft.com/dotnet/runtime:6.0
 => [build 1/8] FROM mcr.microsoft.com/dotnet/sdk:6.0
 => [internal] load build context
 => => transferring context: 5.60kB
 => [base 1/2] FROM mcr.microsoft.com/dotnet/runtime:6.0
 => [base 2/2] WORKDIR /app
 => [build 2/8] WORKDIR /src
 => [final 1/2] WORKDIR /app
 => [build 3/8] COPY [dotnet-console/dotnet-console.csproj, ./dotnet-console/dotnet-console.csproj]
 => [build 4/8] COPY [unit/unit.csproj, ./unit/unit.csproj]
 => [build 5/8] COPY [dotnet-console.sln, .]
 => [build 6/8] RUN dotnet restore
 => [build 7/8] COPY . .
 => [build 8/8] RUN dotnet publish "./dotnet-console/dotnet-console.csproj" -c Release -o /app/publish
 => [final 2/2] COPY --from=build /app/publish .
 => exporting to image
 => => exporting layers
 => => writing image sha256:1e11153b9afc067ee20a7d85c2d234d254c2a836d89f56340630dc51aab11939
 => => naming to docker.io/library/dotnet-console:0418-093553
```

You can see that it runs stage 1/2 (build), then 2/2 (final), but there are three stages! Very confusing. In version 18.09, Docker introduced BuildKit for optimizing builds and later made it the default. BuildKit sees that the test stage has no output used in the final stage, so why run it?

> The Docker Desktop output is very different for BuildKit with colors and hidden output on step completion. You can get the old output with `--progress plain`, which is helpful in debugging.

Turning off BuildKit will run all the stages one line at a time (hence the 19 steps below).

```text
Sending build context to Docker daemon  15.36kB
Step 1/19 : FROM mcr.microsoft.com/dotnet/runtime:6.0 AS base
 ---> 6673acd4c4b4
Step 2/19 : WORKDIR /app
...
Step 10/19 : RUN dotnet publish "./dotnet-console/dotnet-console.csproj" -c Release -o /app/publish
...
Step 15/19 : RUN dotnet test --logger "trx;LogFileName=UnitTests.trx" --results-directory /out/testresults /p:CollectCoverage=true /p:CoverletOutputFormat=cobertura /p:CoverletOutput=/out/testresults/coverage/
...
Step 19/19 : ENTRYPOINT ["dotnet", "dotnet-console.dll"]
...
```

> Set the environment variable `DOCKER_BUILDKIT` to 0 to disable it, 1 to turn it back on.

## Testing BuildKit

To test running tests, I created four Dockerfiles.

Dockerfile-3stage
: This is the one from above and works fine in Azure DevOps, but not with BuildKit

Dockerfile-3stage-with-copy
: This one creates a tiny file in the `test` stage and copies it in the `final` stage forcing Docker BuildKit to run the `test` stage. Although the test runs, BuildKit removes the label and you can't get the output.

Dockerfile-2stage
: This does the test in the `build` stage. The test runs, but the output is unavailable.

Dockerfile-2stage-copying-test
: This is a two-stage file, but the `final` stage copies the test output. This works with BuildKit on or off, but has the disadvantage of polluting the final image with test output.

| Dockerfile                     | BuildKit | Build Switch | Tests Run | Test Container |
| ------------------------------ | -------- | ------------ | --------- | -------------- |
| Dockerfile-3stage              | Yes      |              | ❌         | ❌              |
|                                | Yes      | --rm         | ❌         | ❌              |
|                                | No       |              | ✅         | ✅              |
|                                | No       | --rm         | ✅         | ✅              |
| Dockerfile-3stage-with-copy    | Yes      |              | ✅         | ❌              |
|                                | Yes      | --rm         | ✅         | ❌              |
|                                | No       |              | ✅         | ✅              |
|                                | No       | --rm         | ✅         | ✅              |
| Dockerfile-2stage              | Yes      |              | ✅         | ❌              |
|                                | Yes      | --rm         | ✅         | ❌              |
|                                | No       |              | ✅         | ✅              |
|                                | No       | --rm         | ✅         | ✅              |
| Dockerfile-2stage-copying-test | Yes      |              | ✅         | ✅              |
|                                | Yes      | --rm         | ✅         | ✅              |
|                                | No       |              | ✅         | ✅              |
|                                | No       | --rm         | ✅         | ✅              |

## The End

Running in Azure DevOps, most of the Dockerfiles wills work. If you want to get test results out or even run a test stage, simply turning off BuildKit may be easiest -- but will slow down your local Docker builds.

## Links

* [My source code for this blog post](https://github.com/Seekatar/dotnet-console) that has a trivial C# app, the Dockerfiles, and build.yml.
* [My Azure DevOps pipeline](https://dev.azure.com/MrSeekatar/PipelineTest/_build/results?buildId=657&view=results) that gets test output.
* [Enabling BuildKit in Azure DevOps](https://docs.microsoft.com/en-us/azure/devops/pipelines/ecosystems/containers/build-image?view=azure-devops#how-do-i-set-the-buildkit-variable-for-my-docker-builds)
* [Build images with BuildKit](https://docs.docker.com/develop/develop-images/build_enhancements/) on Docker's site
* [Publishing ASP.NET Core unit test results and code coverage to Azure DevOps using Docker Images](https://medium.com/@harioverhere/running-asp-net-52a6ed92375b) by Haripraghash Subramaniam


