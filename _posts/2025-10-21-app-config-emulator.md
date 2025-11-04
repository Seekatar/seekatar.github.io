---
title: App Configuration Emulator for Local Development
tags:
 - azure
 - app-configuration
 - emulator
excerpt: Using an App Configuration emulator for local development in Docker
cover: /assets/images/leaf14.png
comments: true
layout: article
key: 20251021
---
![image]({{ page.cover }}){: width="{{ site.imageWidth }}" }

In this post I'll cover using the [Azure App Configuration emulator](https://learn.microsoft.com/en-us/azure/azure-app-configuration/emulator-overview?tabs=docker) for local development.

The App Configuration emulator seems to be a pretty good substitute for the real service for local development. If you don't have permissions to create resources in Azure, or want to do PoCs, or do some offline development, it works well. As of October 2025 all the APIs are available, except the snapshot feature. Unlike the Event Hubs emulator, which I discussed in my previous [post](/2025/10/16/eventhub-emulator.html), it doesn't appear that there are restrictions on the number of items you can add to the App Configuration emulator.

## Setup

You need a version of Docker running locally (I have tested [Rancher Desktop](https://rancherdesktop.io/), but others should work.) There isn't much other setup needed. You'll probably want to create a folder on your local machine to hold the persistent data for the emulator. On a Mac or Linux machine you will have to `chmod 0777` the folder so Docker can read and write to it.

## Running locally

To start it in Docker with a volume for persistence, you can use this command (replace `\` with `` ` `` for PowerShell):

```bash
docker run --detach --publish 8483:8483 \
    --volume "/localFolderName:/app/.aace" \
    --env Tenant:AnonymousAuthEnabled=true \
    --env Authentication:Anonymous:AnonymousUserRole=Owner \
    --name appconfig \
    mcr.microsoft.com/azure-app-configuration/app-configuration-emulator:1.0.0-preview
```

> For those new to Docker, this gets and runs the 1.0.0-preview version of the App Configuration emulator image from Microsoft's container registry. It maps the app's port 8483 to your local machine's port 8483, and mounts /localFolderName into the container for persistence. It also enables anonymous authentication with Owner role so you can use the portal without credentials. Finally, it names the container `appconfig` so you can refer to it later instead of using the container ID or generated name.

Once it is started, you can hit its portal at `http://localhost:8483`. See the [doc](https://learn.microsoft.com/en-us/azure/azure-app-configuration/emulator-overview?tabs=docker#emulator-in-action) for details on using it. Its portal is sufficient for basic CRUD operations, but not as feature-rich as the Azure Portal. One thing that the Azure portal has is a way to split keys into their hierarchical parts for easier viewing. For example, a key named `MyApp:Logging:LogLevel:Default` can be shown as a hierarchy of folders in the Azure portal, but just as a string in the emulator's.

![Azure](/assets/images/2025-10-21-azure.png)
*Azure Portal.*{: .image-caption}

![Azure](/assets/images/2025-10-21-emulator.png)
*App Config Emulator.*{: .image-caption}

It's key and label filtering is a bit quirky. It only filters by prefix, and you must have a trailing `*` to get correct results. Valid examples are: `MyApp*` or `MyApp:Logging*`. Invalid examples are `*Logging*` or `Logging`.

They have a [.NET example](https://github.com/Azure/AppConfiguration-Emulator/blob/main/examples/dotnet-sdk/Demo/Program.cs) in the repo, which uses HMAC auth, which is annoying since the default is to use anonymous auth (for the portal). After banging my head against trying to get anonymous auth to work with the SDK, I found I could update the container's configuration to do both methods. Here's a Docker compose file I use. You will need to set the `APPCONFIG_PATH` environment variable to point to your local folder for persistence.

```yaml
version: '3.8'
services:
  appconfig:
    image: mcr.microsoft.com/azure-app-configuration/app-configuration-emulator:1.0.0-preview
    ports:
      - "8483:8483"
    volumes:
      - "${APPCONFIG_PATH}:/app/.aace"
    environment:
      Tenant__AnonymousAuthEnabled: true
      Authentication__Anonymous__AnonymousUserRole: "Owner"
      Tenant__HmacSha256Enabled: true
      Tenant__AccessKeys__0__Id: "emulator-test-id"
      Tenant__AccessKeys__0__Secret: "abcdefghijklmnopqrstuvwxyz1234567890"
    restart: unless-stopped
```

You can also use the App Configuration [REST API](https://learn.microsoft.com/en-us/azure/azure-app-configuration/rest-api) on the emulator. Here's snippet from a PowerShell function I created to import values into the emulator that are in the same format that [az appconfig kv import](https://learn.microsoft.com/en-us/azure/azure-app-configuration/howto-import-export-data?tabs=azure-cli#import-data-from-a-configuration-file) uses for its imports.

```powershell
$apiVersion="1.0"
$separator=":"

$values = Get-Content -Path $ImportFile | ConvertFrom-Json
$prefix = ((Split-Path $ImportFile -LeafBase) -split '-')[0]

foreach ($v in (Get-Member -InputObject $values -MemberType NoteProperty)) {
    $name = $v.Name
    $Key = "$prefix$separator$($v.Name)"
    $value = @{
        value = $values.$name
    }
    Invoke-RestMethod -Uri "$BaseUri/kv/${Key}?api-version=$apiVersion$labelValue" `
                      -Method PUT `
                      -Body $($value | ConvertTo-Json) `
                      -Headers @{ "Content-Type" = "application/vnd.microsoft.appconfig.kv+json" }
}
```

That snippet only does non-secret values. The full script also imports secrets by getting the secret's name from the JSON then getting its value from the Azure KeyVault. I used [az keyvault secret show](https://learn.microsoft.com/en-us/cli/azure/keyvault/secret?view=azure-cli-latest#az-keyvault-secret-show) to do that.

## Stopping it

If you started it with Docker run you can stop it with this. If `--rm` was used on start, this also destroys the container

```bash
docker stop appconfig
```

If you used Docker compose:

```bash
docker compose down # destroys the container
# or
docker compose stop # stops without destroying
```

I recommend mapping a volume for persistence and always making a new container. You *could* keep the state in the container, but that makes it harder to upgrade or recreate the container.

To wipe out all data, stop the container and delete the files in the local folder.

## Configuration

Unlike the Event Hubs emulator, there isn't much configuration needed to run App Configuration. You can use the portal or API to view or create keys.

## Using in .NET

To use the emulator in .NET, there are a few minor differences from using the real service. The connection string will be different and you won't use the `credentials` parameter for the `AddAzureAppConfiguration.Connect` method. Here's a snippet that will use the emulator if configured, otherwise it will use Azure.

```csharp
// DefaultAzureCredential is not recommended for the Production
var cred = string.IsNullOrEmpty(emulatorUri) ? new DefaultAzureCredential() : null;

configuration.AddAzureAppConfiguration(options =>
{
    if (cred is null)
    {
        options.Connect(connStr);
    }
    else
    {
        options.Connect(new Uri(connStr), cred);
    }
    ...
});
```

If you use Azure Key Vault-backed keys for Azure App Configuration, you won't use them with emulator, so you won't have call `ConfigureKeyVault` to authenticate to it.

## Summary

This was a quick tour using the Azure App Configuration emulator for local development. It was pretty easy to set up and use, aside from the issue of getting both anonymous and HMAC auth working together, but now you know how to resolve that.

## Troubleshooting

Use `docker logs appconfig` to see the logs. The last few messages should be:

```text
Hosting environment: Production
Content root path: /app
Now listening on: http://0.0.0.0:8483
Application started. Press Ctrl+C to shut down.
```

Otherwise, if you get errors, getting the logs again will show more details.

## Links

- [Azure App Configuration emulator overview](https://learn.microsoft.com/en-us/azure/azure-app-configuration/emulator-overview?tabs=docker)
- [Repository](https://github.com/Azure/AppConfiguration-Emulator) with samples
- [REST API](https://learn.microsoft.com/en-us/azure/azure-app-configuration/rest-api) for App Configuration
- [Azure CLI app config import](https://learn.microsoft.com/en-us/azure/azure-app-configuration/howto-import-export-data?tabs=azure-cli#import-data-from-a-configuration-file)
