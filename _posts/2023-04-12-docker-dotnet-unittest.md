---
# author: seekatar
title: 'Running .NET Unit tests in Docker [Update]'
tags:
 - docker
 - dotnet
 - unittest
 - xunit
excerpt: Run unit tests in Docker and extract results
cover: /assets/images/leaf1.jpg
comments: true
layout: article
key: apr-12-2023
---

![image]({{ page.cover }}){: width="{{ site.imageWidth }}" }

> I have updated the BuildKit section below to have a much-improved method of getting output from a build if using BuildKit, which seems to be the future of Docker builds.

## Using BuildKit UPDATED

> This section was updated in June 2023 to use this improved method of getting logs in BuildKit.

BuildKit makes your builds much faster. It is smart about transferring data, running stages in parallel, and skipping stages altogether if the output isn't used in the final stage. That last little feature breaks the method above since the test stage doesn't have output used in the final stage, and it will be skipped. To get around this you can use BuildKits optimizations, and `docker build --output` to get build and test output quite easily.

Here's the `BuildKit-4-stage.Dockerfile` from the repo, which should look pretty familiar since it runs the same steps, just broken up differently.

```dockerfile
FROM mcr.microsoft.com/dotnet/runtime:6.0 AS base

FROM mcr.microsoft.com/dotnet/sdk:6.0 AS build-test
WORKDIR /src
COPY ["dotnet-console/dotnet-console.csproj", "./dotnet-console/dotnet-console.csproj"]
COPY ["unit/unit.csproj", "./unit/unit.csproj"]
COPY ["dotnet-console.sln", "."]
RUN dotnet restore

COPY . .
RUN dotnet publish "./dotnet-console/dotnet-console.csproj" -c Release -o /app/publish /flp:logfile=/logs/Build.log --no-restore

WORKDIR /src/unit
RUN dotnet test --logger "trx;LogFileName=UnitTests.trx" --no-restore --results-directory /out/testresults /p:CollectCoverage=true /p:CoverletOutputFormat=cobertura /p:CoverletOutput=/out/testresults/coverage/; exit 0

WORKDIR /src

FROM scratch as test-results
COPY --from=build-test /out/testresults /testresults
COPY --from=build-test /logs /logs

FROM base AS final
WORKDIR /app
COPY --from=build-test /app/publish .
ENTRYPOINT ["dotnet", "dotnet-console.dll"]
```

The `build-test` stage does the publish (with build) and test. Nothing too special here. (These could be split into separate stages, and `BuildKit-6-stage.Dockerfile` does that.)

The `test-results` stage is a bit more interesting. It uses [scratch](https://hub.docker.com/_/scratch) as its parent layer. The is a special image that has nothing at all in it and is used for building base images, or in cases like this. In this stage, I copy build and test output from the `build-test` stage to this layer. Then, to do the build and get the output with BuildKit on, I run this:

```bash
cd src
docker build --file ../DevOps/Docker/BuildKit-5-stage.Dockerfile \
             --target 'test-results' \
             --output 'type=local,dest=../out' .
```

Using `--target 'test-results'` tells the build to stop on that stage, and `--output 'type=local,dest=../out'` (BuildKit-only option) tells it to copy all the content of the layer to the `../out` folder. It's important not to put it in the `src` (or `.`, which is the build context) folder as that will trigger a rebuild of layers. After this step, we have out build and test output.

```text
├───src
└───out
    ├───logs
    │       Build.log
    │
    └───testresults
        │   UnitTests.trx
        │
        └───coverage
                coverage.cobertura.xml
```

A sharp-eyed reader my have noticed at the end of the `RUN dotnet test` line is `; exit 0`. This prevents a failure of the test to stop the Dockerfile and skip getting the test output. After running this command I have code to check to see if the build succeeded (`$LASTEXITCODE` == 0) and test completed before continuing.

```powershell
if ($LASTEXITCODE -eq 0) {
    $file = '..\out\testresults\UnitTests.trx'
    $test = [xml](Get-Content $file)
    if ($test.TestRun.ResultSummary.Counters.failed -ne '0') {
        $global:LASTEXITCODE = 1
        throw "Tests failed with $($test.TestRun.ResultSummary.Counters.failed) failures. See $file for details"
    }
  ...
```

Now to create the final layer, we call `docker build` again, with no `--target`

```bash
docker build --file ../DevOps/Docker/BuildKit-4-stage.Dockerfile --tag dotnet-console .
```

And we're done! This method seems cleaner that having to create the test layer, and copy the log files out. One thing you may wonder is, doesn't this double your build time since I do `docker build` twice? Actually, no, due to the magic of caching. Here's the output from the second build which runs almost instantly:

```pwsh
[+] Building 0.2s (20/20) FINISHED
 => [internal] load .dockerignore                                        ... 0.0s
 => => transferring context: 2B                                          ... 0.0s
 => [internal] load build definition from BuildKit-4-stage.Dockerfile    ... 0.0s
 => => transferring dockerfile: 1.26kB                                   ... 0.0s
 => [internal] load metadata for mcr.microsoft.com/dotnet/sdk:6.0        ... 0.1s
 => [internal] load metadata for mcr.microsoft.com/dotnet/runtime:6.0    ... 0.1s
 => [build-test  1/11] FROM mcr.microsoft.com/dotnet/sdk:6.0@sha256:a3b  ... 0.0s
 => [base 1/1] FROM mcr.microsoft.com/dotnet/runtime:6.0@sha256:87217a1  ... 0.0s
 => [internal] load build context                                        ... 0.1s
 => => transferring context: 28.70kB                                     ... 0.0s
 => CACHED [final 1/2] WORKDIR /app                                      ... 0.0s
 => CACHED [build-test  2/11] WORKDIR /src                               ... 0.0s
 => CACHED [build-test  3/11] COPY [dotnet-console/dotnet-console.cspro  ... 0.0s
 => CACHED [build-test  4/11] COPY [unit/unit.csproj, ./unit/unit.cspro  ... 0.0s
 => CACHED [build-test  5/11] COPY [dotnet-console.sln, .]               ... 0.0s
 => CACHED [build-test  6/11] RUN dotnet restore                         ... 0.0s
 => CACHED [build-test  7/11] COPY . .                                   ... 0.0s
 => CACHED [build-test  8/11] RUN dotnet publish "./dotnet-console/dotn  ... 0.0s
 => CACHED [build-test  9/11] WORKDIR /src/unit                          ... 0.0s
 => CACHED [build-test 10/11] RUN dotnet test --logger "trx;LogFileName  ... 0.0s
 => CACHED [build-test 11/11] WORKDIR /src                               ... 0.0s
 => CACHED [final 2/2] COPY --from=build-test /app/publish .             ... 0.0s
 => exporting to image                                                   ... 0.0s
 => => exporting layers                                                  ... 0.0s
 => => writing image sha256:f2ac93cde4800675c1f34ac5bdd8700895087087e66  ... 0.0s
 => => naming to docker.io/library/dotnet-console
```

You can see that everything is cached from the first `docker build --target test-result` we ran the first time. No rebuilding.

> By default when running locally, BuildKit hides the output of each layer after it runs, so if you need to see output for diagnostic purposes, etc. add `--progress plain`

> Note as of this writing Azure DevOps does _not_ have BuildKit enabled by default. If your build box has it on and you explicitly turn it off (DOCKER_BUILDKIT=0), you will get a warning that the default builder will be going away in a future version.

## Testing BuildKit

To test running tests, I created several Dockerfiles.

Dockerfile-3stage
: This is the one from [above](#getting-the-test-output-locally) and works fine in Azure DevOps, but not with BuildKit

Dockerfile-3stage-with-copy
: This one creates a tiny file in the `test` stage and copies it in the `final` stage forcing Docker BuildKit to run the `test` stage. Although the test runs, BuildKit removes the label and you can't get the output.

Dockerfile-2stage
: This does the test in the `build` stage. The test runs, but the output is unavailable.

Dockerfile-2stage-copying-test
: This is a two-stage file, but the `final` stage copies the test output. This works with BuildKit on or off, but has the disadvantage of polluting the final image with test output.

BuildKit-4-stage.Dockerfile
: This uses BuildKit and is detailed [above](#using-buildkit-updated). This seems the cleanest method of all.

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
| BuildKit-4-stage.Dockerfile    | Yes      |              | ✅         | ✅              |
|                                | Yes      | --rm         | ✅         | ✅              |
|                                | n/a      |              |             |                 |
|                                | n/a      |              |             |                 |

## Adding Unit Test to Docker the Old Way

> This is the text from the original blog post. It's an alternative to the cleaner BuildKit method above.

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

Like getting the results locally, you pull the content from the container, then use the publish tasks to get them into DevOps for you.

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

## The End

Running in Azure DevOps, most of the Dockerfiles will work. With the update to this blog about BuildKit, I think that's the cleanest and fastest way to do builds.

## Links

* [My source code for this blog post](https://github.com/Seekatar/dotnet-console) that has a trivial C# app, the Dockerfiles, and build.yml.
* [My Azure DevOps pipeline](https://dev.azure.com/MrSeekatar/PipelineTest/_build/results?buildId=657&view=results) that gets test output.
* [Enabling BuildKit in Azure DevOps](https://docs.microsoft.com/en-us/azure/devops/pipelines/ecosystems/containers/build-image?view=azure-devops#how-do-i-set-the-buildkit-variable-for-my-docker-builds)
* [Publishing ASP.NET Core unit test results and code coverage to Azure DevOps using Docker Images](https://medium.com/@harioverhere/running-asp-net-52a6ed92375b) by Haripraghash Subramaniam
* [Exporting unit test results from a multi-stage docker build](https://kevsoft.net/2021/08/09/exporting-unit-test-results-from-a-multi-stage-docker-build.html) by Kevin Smith where I learned about `--output`
* [Docker Doc: Build images with BuildKit](https://docs.docker.com/develop/develop-images/build_enhancements/) on Docker's site
* [Docker Doc: Multi-stage builds](https://docs.docker.com/build/building/multi-stage/)
* [Docker Doc: Scratch base image](https://docs.docker.com/build/building/base-images/)
