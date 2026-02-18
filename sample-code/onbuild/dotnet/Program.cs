using System.Runtime.InteropServices;

Console.WriteLine("=== .NET Information ===");
Console.WriteLine($"  .NET Version:        {Environment.Version}");
Console.WriteLine($"  Runtime Identifier:  {RuntimeInformation.RuntimeIdentifier}");
Console.WriteLine($"  Framework:           {RuntimeInformation.FrameworkDescription}");

Console.WriteLine();
Console.WriteLine("=== System Information ===");
Console.WriteLine($"  OS:                  {RuntimeInformation.OSDescription}");
Console.WriteLine($"  OS Architecture:     {RuntimeInformation.OSArchitecture}");
Console.WriteLine($"  Process Architecture:{RuntimeInformation.ProcessArchitecture}");
Console.WriteLine($"  Machine Name:        {Environment.MachineName}");
Console.WriteLine($"  User Name:           {Environment.UserName}");
Console.WriteLine($"  Processor Count:     {Environment.ProcessorCount}");
Console.WriteLine($"  64-bit OS:           {Environment.Is64BitOperatingSystem}");
Console.WriteLine($"  64-bit Process:      {Environment.Is64BitProcess}");
