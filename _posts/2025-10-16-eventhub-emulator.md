---
title: Event Hubs Emulator for Local Development
tags:
 - azure
 - eventhub
 - emulator
excerpt: Using an Event Hubs emulator for local development in Docker
cover: /assets/images/leaf13.png
comments: true
layout: article
key: 20251016
---
![image]({{ page.cover }}){: width="{{ site.imageWidth }}" }

In this post I'll cover using the [Azure Event Hubs emulator](https://learn.microsoft.com/en-us/azure/event-hubs/overview-emulator) for local development and testing of Event Hub producers and consumers.

Using an Azure-based hub works fine if you're the only producer and consumer. If not, you may not get events you produce locally since they could be processed by a remote consumer. Also, your local consumer may start getting events produced by remote producers. This can be frustrating when you're trying to test a producer and consumer locally. A `GroupId` can help with consuming, but not producing. The emulator solves this problem by running a local instance of Event Hubs in Docker.

The emulator does have limitations, as the [doc](https://learn.microsoft.com/en-us/azure/event-hubs/overview-emulator#usage-quotas) outlines, but is robust enough for testing producing and consuming messages from multiple Event Hubs.

## Setup

You need a version of Docker running locally that supports `docker-compose`. (I have tested [Rancher Desktop](https://rancherdesktop.io/), but others should work.) Then clone the emulator installer's [repository](https://github.com/Azure/azure-event-hubs-emulator-installer).

```bash
cd ~/code # I'll use this as the example code folder
git clone git@github.com:Azure/azure-event-hubs-emulator-installer.git
```

It has sample scripts and helpers for starting and stopping the emulator in Docker. That repo hasn't been updated in over a year (as of October 2025), but the [image](https://mcr.microsoft.com/en-us/artifact/mar/azure-messaging/eventhubs-emulator/tags) it runs has been updated more recently.

## Running locally

To start it, run `LaunchEmulator.sh` as follows. If it is already running it will restart it, which you need to do to pick up any configuration changes.

```bash
cd ~/code/azure-event-hubs-emulator-installer/EventHub-Emulator/Scripts/Common
chmod +x ./LaunchEmulator.sh
./LaunchEmulator.sh
```

Then run one of the samples (you may want to update the TFM from .NET 6). This one uses the Event Hub library.

```bash
cd ~/code/azure-event-hubs-emulator-installer/Sample-Code-Snippets/dotnet/EventHubs-Emulator-Demo/EventHubs-Emulator-Demo
dotnet run
```

This one uses the Kafka library. For Kafka, you may see some error messages at the start of a producer or consumer, which are benign. If they persist, you have a problem.

```bash
cd ~/code/azure-event-hubs-emulator-installer/Sample-Code-Snippets/dotnet/EventHubs-Emulator-Kafka-Demo/EventHubs-Emulator-Kafka-Demo
dotnet run

...

%3|1759251698.801|FAIL|rdkafka#consumer-1| [thrd:sasl_plaintext://localhost:9092/bootstrap]: sasl_plaintext://localhost:9092/bootstrap: Connect to ipv6#[::1]:9092 failed: Connection refused (after 1ms in state CONNECT)
%3|1759251698.801|ERROR|rdkafka#consumer-1| [thrd:sasl_plaintext://localhost:9092/bootstrap]: 1/1 brokers are down
```

## Stopping it

```bash
./LaunchEmulator.sh --compose-down=Y
```

## Configuration

When starting it, you supply a config file as a parameter. Below is a sample one with an extra event hub added. Note that `Type` and `Name` can't be changed. `eh1` is their test event hub used by the samples. Changing `LoggingConfig` to `Console` seems to break it (see [below](#troubleshooting)).

> The config file is pretty simple, but there is a schema file in `EventHub-Emulator/Schema/Config-schema.json`. If you  add `"$schema": "<path>/Schema/Config-schema.json"` you can get some intellisense, or just read it.

It always adds `$default` to the `ConsumerGroups`. If you use that in your code (or use the Kafka client), you can remove all of them from the configuration. If you use the Event Hubs SDK and set the `consumerGroup` to something other than `$default`, you will need to add it to the configuration. Case doesn't matter since the emulator and Azure always fold the name to lowercase.

```json
{
    "UserConfig": {
        "NamespaceConfig": [
            {
                "Type": "EventHub",
                "Name": "emulatorNs1",
                "Entities": [
                    {
                        "Name": "eh1",
                        "PartitionCount": 2,
                        "ConsumerGroups": [
                            {
                                "Name": "cg1"
                            }
                        ]
                    },
                    {
                        "Name": "propensity-model-patient-topic",
                        "PartitionCount": 2,
                        "ConsumerGroups": []
                    }
                ]
            }
        ],
        "LoggingConfig": {
            "Type": "File"
        }
    }
}
```

Then to launch it with the config file:

```bash
./LaunchEmulator.sh --CONFIG_PATH=$configFile --ACCEPT_EULA=Y
```

### Event Hub Client Configuration

You can look at the sample for full details, but what you need to know when connecting to the emulator is:

- Connection string, which is always `Endpoint=sb://localhost;SharedAccessKeyName=RootManageSharedAccessKey;SharedAccessKey=EMULATOR_DEV_SAS_VALUE;UseDevelopmentEmulator=true;`
- Your hub's name
- Some unique id for blob storage for consumers

### Kafka Client Configuration

These are the values you use when configuring the Confluent Kafka producer and consumer clients for the emulator.

```csharp
BootstrapServers = "localhost:9092",
SecurityProtocol = SecurityProtocol.SaslPlaintext,
SaslMechanism = SaslMechanism.Plain,
SaslUsername = "$ConnectionString",
SaslPassword = "Endpoint=sb://localhost;SharedAccessKeyName=RootManageSharedAccessKey;SharedAccessKey=SAS_KEY_VALUE;UseDevelopmentEmulator=true;"
```

## Summary

This was a quick tour using the Azure Event Hubs for local development. It was pretty easy to set up and use. The emulators has enough features to allow you to do a variety of tests with producers and consumers locally that can then be deployed to Azure.

## Troubleshooting

Always look at the output from `LaunchEmulator.sh` since it will have errors that prevent the containers from starting. If it succeeds, use `docker logs eventhubs-emulator` to see the logs. The last message should be:

```text
Emulator Service is Successfully Up!
```

### Messages Not Getting Consumed

At times, I have noticed a significant delay from when a producer sends a message to when the consumer receives it.

### `Broker: Unknown topic or partition`

Check the configuration file to make sure you added your Event Hub to the `Entities` section. Remember that changes require a restart. You can view the container's logs to see all of the topics it registered. (See below)

### `The messaging entity 'emulatorns1:eventhub:test-topic~16383|test123' already exists.`

This means you probably have tried to add two consumer groups named `test123` that are the same, but different case.

### `The messaging entity 'testing-ns-test:eventhub:test-topic~32766|aaaaaaa' could not be found`

The configuration file is missing the consume group `aaaaaa` for the hub `test-topic`

### SSL Errors

These usually happen when the `SecurityProtocol` or `SaslMechanism` are not set to the values [above](#kafka%20client%20configuration)

### General Errors

> The [doc](https://learn.microsoft.com/en-us/azure/event-hubs/overview-emulator#logs-for-debugging) says you can shell into the container and get `/home/app/EmulatorLogs`, but I haven't been able to run `sh` or `bash` via `docker exec`. I suspect the base image is not locked down.

If compose succeeds, run this to see the startup messages:

```bash
docker logs eventhubs-emulator
```

This is normal output with `LoggingConfig` set to `File`

```text
fail: a.D.aDr[0]
      Emulator Start up probe Unsuccessful. MetadataStore Health status: Unhealthy BlobStore Health status: Healthy
fail: Microsoft.Extensions.Diagnostics.HealthChecks.DefaultHealthCheckService[103]
      Health check Emulator Health Check with status Unhealthy completed after 3120.4613ms with message 'Emulator Start up probe Unsuccessful. MetadataStore Health status: Unhealthy BlobStore Health status: Healthy'
Retry 1 encountered an exception: Emulator Health Check failed.. Waiting 00:00:00 before next retry.
info: a.D.aDj[0]
      Emulator Service is Launching On Platform:CBL-Mariner/Linux,Arm64
info: a.D.aDj[0]
      Instantiating service components
info: a.D.aDj[0]
      Creating namespace, entities and consumer groups
info: a.D.aDS[0]
      Emulator is launching with config : {"LoggingConfig":{"Type":"File"},"NamespaceConfig":[{"Type":"EventHub","Name":"emulatorns1","Entities":[{"Name":"eh1","PartitionCount":2,"ConsumerGroups":[{"Name":"cg1"},{"Name":"$default"}]},{"Name":"propensity-model-patient-topic","PartitionCount":2,"ConsumerGroups":[{"Name":"cg1"},{"Name":"$default"}]},{"Name":"propensity-cancel-run-topic","PartitionCount":2,"ConsumerGroups":[{"Name":"cg1"},{"Name":"$default"}]},{"Name":"propensity-patient-modeled-topic","PartitionCount":2,"ConsumerGroups":[{"Name":"cg1"},{"Name":"$default"}]},{"Name":"propensity-patient-failed-topic","PartitionCount":2,"ConsumerGroups":[{"Name":"cg1"},{"Name":"$default"}]},{"Name":"propensity-run-canceled-topic","PartitionCount":2,"ConsumerGroups":[{"Name":"cg1"},{"Name":"$default"}]}]}]}
info: a.D.aDj[0]
      Emulator Service is Successfully Up! ; Use connection string: "Endpoint=sb://localhost;SharedAccessKeyName=RootManageSharedAccessKey;SharedAccessKey=SAS_KEY_VALUE;UseDevelopmentEmulator=true;". For more networking-options refer: "https://github.com/Azure/azure-event-hubs-emulator-installer?tab=readme-ov-file#networking-options"
/Users/jwallace/code/azure-event-hubs-emulator-installer/Sample-Code-Snippets/dotnet/EventHubs-Emulator-Kafka-Demo/EventHubs-Emulator-Kafka-Demo
```

If set to `Console` you get a bunch of errors and producers seem to work, but consumers time out in example

```text
fail: a.D.aDr[0]
      Emulator Start up probe Unsuccessful. MetadataStore Health status: Unhealthy BlobStore Health status: Healthy
fail: Microsoft.Extensions.Diagnostics.HealthChecks.DefaultHealthCheckService[103]
      Health check Emulator Health Check with status Unhealthy completed after 3068.1163ms with message 'Emulator Start up probe Unsuccessful. MetadataStore Health status: Unhealthy BlobStore Health status: Healthy'
Retry 1 encountered an exception: Emulator Health Check failed.. Waiting 00:00:00 before next retry.
[16:42:48 WRN] <Trc Id="60000" Ch="Operational" Lvl="Warning" Kw="4000000000011110" UTC="2025-09-30T16:42:48.556Z" Msg="Exception occurred while creating performance counters. Exception message &amp;apos;System.PlatformNotSupportedException: Performance Counters are not supported on this platform.&#xA;   at System.Diagnostics.PerformanceData.CounterSet..ctor(Guid providerGuid, Guid counterSetGuid, CounterSetInstanceType instanceType)&#xA;   at I.If.ad()&#xA;   at I.If.ab()&#xA;   at I.IA.A(PerformanceCounterLevel)&amp;apos;." />
[16:42:48 WRN] <Trc Id="60000" Ch="Operational" Lvl="Warning" Kw="4000000000011110" UTC="2025-09-30T16:42:48.569Z" Msg="Exception occurred while creating performance counters. Exception message &amp;apos;System.PlatformNotSupportedException: Performance Counters are not supported on this platform.&#xA;   at System.Diagnostics.PerformanceData.CounterSet..ctor(Guid providerGuid, Guid counterSetGuid, CounterSetInstanceType instanceType)&#xA;   at I.Id.ab()&#xA;   at I.IA.A(PerformanceCounterLevel)&amp;apos;." />
[16:42:48 WRN] <Trc Id="60000" Ch="Operational" Lvl="Warning" Kw="4000000000011110" UTC="2025-09-30T16:42:48.588Z" Msg="Exception occurred while creating performance counters. Exception message &amp;apos;System.PlatformNotSupportedException: Performance Counters are not supported on this platform.&#xA;   at System.Diagnostics.PerformanceData.CounterSet..ctor(Guid providerGuid, Guid counterSetGuid, CounterSetInstanceType instanceType)&#xA;   at I.Id.ab()&#xA;   at I.IA.A(PerformanceCounterLevel)&amp;apos;." />
[16:42:48 WRN] <Trc Id="30633" Ch="Debug" Lvl="Warning" Kw="1000000000001008" UTC="2025-09-30T16:42:48.642Z" Msg="InternalId: N/A, Operation: KafkaConnection.GetTenant, Warning: Getting the tenant failed for $emulatorns1, so subscription ID could not be populated., RequestId: NoCorrelationRequestId, Namespace: emulatorns1" />
[16:42:48 WRN] <Trc Id="60000" Ch="Operational" Lvl="Warning" Kw="4000000000011110" UTC="2025-09-30T16:42:48.699Z" Msg="Exception occurred while creating performance counters. Exception message &amp;apos;System.PlatformNotSupportedException: Performance Counters are not supported on this platform.&#xA;   at System.Diagnostics.PerformanceData.CounterSet..ctor(Guid providerGuid, Guid counterSetGuid, CounterSetInstanceType instanceType)&#xA;   at I.IJ.ac()&#xA;   at I.IJ.ab()&#xA;   at I.IA.A(PerformanceCounterLevel)&amp;apos;." />
[16:42:48 WRN] <Trc Id="30633" Ch="Debug" Lvl="Warning" Kw="1000000000001008" UTC="2025-09-30T16:42:48.979Z" Msg="InternalId: N/A, Operation: KafkaConnection.GetTenant, Warning: Getting the tenant failed for $emulatorns1, so subscription ID could not be populated., RequestId: NoCorrelationRequestId, Namespace: emulatorns1" />
[16:42:48 WRN] <Trc Id="30633" Ch="Debug" Lvl="Warning" Kw="1000000000001008" UTC="2025-09-30T16:42:48.993Z" Msg="InternalId: N/A, Operation: KafkaConnection.GetTenant, Warning: Getting the tenant failed for $emulatorns1, so subscription ID could not be populated., RequestId: NoCorrelationRequestId, Namespace: emulatorns1" />
[16:42:50 WRN] <Trc Id="30633" Ch="Debug" Lvl="Warning" Kw="1000000000001008" UTC="2025-09-30T16:42:50.003Z" Msg="InternalId: N/A, Operation: KafkaConnection.GetTenant, Warning: Getting the tenant failed for $emulatorns1, so subscription ID could not be populated., RequestId: NoCorrelationRequestId, Namespace: emulatorns1" />
[16:42:50 WRN] <Trc Id="60004" Ch="Debug" Lvl="Warning" Kw="1000000000011110" UTC="2025-09-30T16:42:50.021Z" Msg="Details: ShouldUseWindowsFabricResolver: Not using SF-based resolver, which is very unexpected. We should almost always use a ServiceFabric-based resolver. ContainerId = 0, useWindowsFabric = False, windowsFabricOnWindowsAzure = False.." />
[16:42:50 WRN] <Trc Id="60004" Ch="Debug" Lvl="Warning" Kw="1000000000011110" UTC="2025-09-30T16:42:50.237Z" Msg="Details: ShouldUseWindowsFabricResolver: Not using SF-based resolver, which is very unexpected. We should almost always use a ServiceFabric-based resolver. ContainerId = 0, useWindowsFabric = False, windowsFabricOnWindowsAzure = False.." />
[16:42:51 WRN] <Trc Id="30902" Ch="Debug" Lvl="Warning" Kw="1000000000000100" UTC="2025-09-30T16:42:51.437Z" Msg="Aborting messaging object. Name = emulatorns1:kafka11, Object type = a.e.aee, Reason = d.dN:An AMQP error occurred (condition=&amp;apos;amqp:connection:forced&amp;apos;).. TrackingId: , SubsystemId: ." />
[16:42:51 WRN] <Trc Id="30633" Ch="Debug" Lvl="Warning" Kw="1000000000001008" UTC="2025-09-30T16:42:51.451Z" Msg="InternalId: N/A, Operation: KafkaConnection.GetTenant, Warning: Getting the tenant failed for $emulatorns1, so subscription ID could not be populated., RequestId: NoCorrelationRequestId, Namespace: emulatorns1" />
[16:42:53 WRN] <Trc Id="30633" Ch="Debug" Lvl="Warning" Kw="1000000000001008" UTC="2025-09-30T16:42:53.454Z" Msg="InternalId: N/A, Operation: KafkaConnection.GetTenant, Warning: Getting the tenant failed for $emulatorns1, so subscription ID could not be populated., RequestId: NoCorrelationRequestId, Namespace: emulatorns1" />
[16:42:57 WRN] <Trc Id="30633" Ch="Debug" Lvl="Warning" Kw="1000000000001008" UTC="2025-09-30T16:42:57.481Z" Msg="InternalId: N/A, Operation: KafkaConnection.GetTenant, Warning: Getting the tenant failed for $emulatorns1, so subscription ID could not be populated., RequestId: NoCorrelationRequestId, Namespace: emulatorns1" />
[16:42:57 WRN] <Trc Id="60004" Ch="Debug" Lvl="Warning" Kw="1000000000011110" UTC="2025-09-30T16:42:57.492Z" Msg="Details: ShouldUseWindowsFabricResolver: Not using SF-based resolver, which is very unexpected. We should almost always use a ServiceFabric-based resolver. ContainerId = 0, useWindowsFabric = False, windowsFabricOnWindowsAzure = False.." />
[16:42:57 WRN] <Trc Id="60004" Ch="Debug" Lvl="Warning" Kw="1000000000011110" UTC="2025-09-30T16:42:57.496Z" Msg="Details: ShouldUseWindowsFabricResolver: Not using SF-based resolver, which is very unexpected. We should almost always use a ServiceFabric-based resolver. ContainerId = 0, useWindowsFabric = False, windowsFabricOnWindowsAzure = False.." />
[16:43:06 WRN] <Trc Id="30902" Ch="Debug" Lvl="Warning" Kw="1000000000000100" UTC="2025-09-30T16:43:06.487Z" Msg="Aborting messaging object. Name = emulatorns1:kafka31, Object type = a.e.aee, Reason = d.dN:An AMQP error occurred (condition=&amp;apos;amqp:connection:forced&amp;apos;).. TrackingId: , SubsystemId: ." />
[16:43:06 WRN] <Trc Id="30633" Ch="Debug" Lvl="Warning" Kw="1000000000001008" UTC="2025-09-30T16:43:06.576Z" Msg="InternalId: N/A, Operation: KafkaConnection.GetTenant, Warning: Getting the tenant failed for $emulatorns1, so subscription ID could not be populated., RequestId: NoCorrelationRequestId, Namespace: emulatorns1" />
[16:43:08 ERR] <Trc Id="30638" Ch="Debug" Lvl="Error" Kw="1000000000001008" UTC="2025-09-30T16:43:08.689Z" Msg="message: GetKafkaCoordinatorAsync:FE00000000050A02000000140E928E88_rdkafka failed for emulatorns1 - 2025-09-30T16:42:48.659-&amp;gt;6:NullReferenceException:Object reference not set to an instance of an object.:0-&amp;gt;2010:NullReferenceException:Object reference not set to an instance of an object.:0-&amp;gt;4008:NullReferenceException:Object reference not set to an instance of an object.:0-&amp;gt;6017:NullReferenceException:Object reference not set to an instance of an object.:0-&amp;gt;8021:NullReferenceException:Object reference not set to an instance of an object.:0-&amp;gt;10018:NullReferenceException:Object reference not set to an instance of an object.:0-&amp;gt;12021:NullReferenceException:Object reference not set to an instance of an object.:0-&amp;gt;14019:NullReferenceException:Object reference not set to an instance of an object.:0-&amp;gt;16019:NullReferenceException:Object reference not set to an instance of an object.:0-&amp;gt;18021:NullReferenceException:Object reference not set to an instance of an object.:0-&amp;gt;20024:timeout:0 | LastException:ExceptionId: 473613e4-462b-4c3e-9b27-0866a8c8dc2b-System.NullReferenceException: Object reference not set to an instance of an object.&#xA;   at Y.Yf.A()&#xA;   at a.F.aFg.A[A](OperationTracker, String, String, Boolean)&#xA;   at a.e.aeI.a(String, String, TimeSpan)" />
[16:43:08 WRN] <Trc Id="30902" Ch="Debug" Lvl="Warning" Kw="1000000000000100" UTC="2025-09-30T16:43:08.698Z" Msg="Aborting messaging object. Name = emulatorns1:kafka5, Object type = a.e.aee, Reason = d.dN:An AMQP error occurred (condition=&amp;apos;amqp:connection:forced&amp;apos;).. TrackingId: , SubsystemId: ." />
```

## Links

- [Azure Event Hubs emulator overview](https://learn.microsoft.com/en-us/azure/event-hubs/overview-emulator)
  - [Usage Quotas](https://learn.microsoft.com/en-us/azure/event-hubs/overview-emulator#usage-quotas)
    - Enough to do simple stuff. 1 namespace, 10 hubs.
- [Test locally by using the Azure Event Hubs emulator](https://learn.microsoft.com/en-us/azure/event-hubs/test-locally-with-event-hub-emulator?source=recommendations&tabs=docker-linux-container%2Cusing-kafka)
- [Installer Repo](https://github.com/Azure/azure-event-hubs-emulator-installer)
