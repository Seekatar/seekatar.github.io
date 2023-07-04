---
title: ASP.NET Authentication & Authorization
tags:
 - dotnet
 - authentication
 - authorization
 - asp.net
excerpt: Exploring ASP.NET Auth
cover: /assets/images/super-natural-1639059.jpg
comments: true
layout: article
key: aspnet-auth
---

![image]({{ page.cover }}){: width="{{ site.imageWidth }}" }

This post explores configuring ASP.NET authentication and authorization (authentication and authorization), in particular multiple methods of doing both. ASP.NET makes it easy to add authentication (Who is the user?) and authorization (Can the user do this?) and in most situations, you don't need to worry about the details.

> I do assume you have some knowledge of ASP.NET and how auth works in general.

For the ASP.NET sample app, I added auth to [this](https://github.com/Seekatar/ioptions-logger-test) repo, which was the basis for a TechTalk I gave at work. It also has code for using other .NET features, but this post is only about the auth.

I decide to dive deeper into ASP.NET auth when I recently added Basic _and_ multiple JWT authentications to a project. It seemed simple, but I did run into some issues when configuring ASP.NET security that raised some questions. I wrote some code to suss out the answers and decided to blog about what I learned.

## Terminology

Here are some basic and ASP.NET terms that I'll be using in this post.

`Authentication (AuthN)`
: The process of determining who a user is. There are various ways this is done, such as with an encoded username and password (Basic Auth), some kind of secure token (JWT) provided by a third party (e.g. Google, Okta, Auth0, or Microsoft), etc. In this sample I mock the authentication by checking a custom header.

`Authorization (AuthZ)`
: The process of determining what a user is allowed to do. This is often done by assigning roles or groups to a user and then checking if the user has the required role to perform an action. In this sample, the user's roles determine access to API endpoints.

`Scheme`
: An arbitrary name you give to an ASP.NET authentication method in your app. In the sample, I have `SchemeA`, `SchemeB`, and `SchemeC`.

`Policy`
: A policy is a way of authorizing a user. Policies in ASP.NET have various criteria for authorizing a user, such as requiring a role, specific authentication scheme, etc. This sample configures various policies for the API.

`Role`
: A role is an attribute of an authenticated user often used for authorization. Most of the policies in this sample require a role.

## Changes to the Sample App

To test various auth scenarios in the sample ASP.NET app, I made the following changes:

- Added three authentication Schemes A, B, and C that all use the same code to authenticate a user.
- Added an `AuthTestController` with a bunch of endpoints for testing scenarios, logging output using `ILogger`
- Updated `Program.cs` to configure authentication and authorization. It was already using the middleware: `app.UseAuthentication();` and `app.UseAuthorization();`
- Added Pester tests to test all the endpoints

## Authenticating User

> For this sample, I'm focused on configuring the authentication and authorization for an ASP.NET API and not concerned about securely authenticating a user. Its implementation of the `AuthenticationHandler` is just for this test and it is not secure by any means. In a real application, you'd use something like JWTs (JSON Web Tokens) for authentication.

Here's the `AuthenticationHandler` implementation for the sample. For authentication, it checks that the user name in a custom header matches the configured name of this handler or a wildcard (`*`). As an authentication handler, this doesn't do the authorization, but it does add the roles from another custom header to the claims. The claims will be used by ASP.NET to do the authorization, as we'll see shortly.

To see what happens during authentication, it logs out when it succeeds. When it fails, ASP.NET will log for us, so no need to do it here.

```csharp
protected override Task<AuthenticateResult> HandleAuthenticateAsync()
{
    var user = Context.Request.Headers["X-Test-User"].ElementAtOrDefault(0);
    if (!string.Equals(user, "User*", StringComparison.OrdinalIgnoreCase) &&
        !(user?.Equals($"User{Options.Name}", StringComparison.OrdinalIgnoreCase) ?? false))
        return Task.FromResult(AuthenticateResult.Fail($"'{user}' was not 'User{Options.Name}'"));

    var claims = new List<Claim>
    {
        new Claim(ClaimTypes.Name, Options.Name),
    };

    var role = Context.Request.Headers["X-Test-Role"].FirstOrDefault();
    if (role is not null) {
        foreach (var r in role.Split(","))
            claims.Add(new Claim(ClaimTypes.Role, r));
    }
    Logger.LogInformation("Scheme{handlerName} was authenticated. Set claims on {user}: {claims}", Options.Name, 
                            user, 
                            string.Join(", ", claims.Select(c => c.Type.Split('/').Last() + " = '" + c.Value + "'")));

    var identity = new ClaimsIdentity(claims, ClaimTypes.Name);
    var principal = new ClaimsPrincipal(identity);
    return Task.FromResult(AuthenticateResult.Success(new AuthenticationTicket(principal, ClaimTypes.Name)));
}

```

## Configuring Authentication

In the `Program.cs`, I call call `builder.Services.AddAuthentication` and add schemes to it. You usually see a string passed into `AddAuthentication` which is the default Scheme that will be used if you don't specify one. This sample tests both cases by using a command-line parameter to set the default Scheme.

> If you only have one scheme, with .NET 7, it will use that as the default automatically (which is a breaking change from .NET 6 as described [here](https://learn.microsoft.com/en-us/dotnet/core/compatibility/aspnet-core/7.0/default-authentication-scheme))

In this case, I add three implementations of `CustomAuthenticationHandler` with different Scheme names. (Its `HandleAuthenticateAsync` method is shown above.)

```csharp
string? defaultScheme = (args.Length > 0 && args[0].StartsWith("Scheme")) ? args[0] : "";

builder.Services
    .AddAuthentication(defaultScheme)
    .AddScheme<MyAuthenticationSchemeOptions, CustomAuthenticationHandler>(SchemeA, options => options.Name = NameClaimA )
    .AddScheme<MyAuthenticationSchemeOptions, CustomAuthenticationHandler>(SchemeB, options => options.Name = NameClaimB )
    .AddScheme<MyAuthenticationSchemeOptions, CustomAuthenticationHandler>(SchemeC, options => options.Name = NameClaimC );
```

## Configuring Authorization

After configuring authentication, I configured authorization by calling `builder.Services.AddAuthorization` and adding policies. I'll use these policies in the controller below to allow access to each method. Policies are optional since you can provide these same details on each controller or controller method, but these allow you to configure authorization in one place and increase usability.

```csharp
builder.Services.AddAuthorization(options =>
{
    // UserA and RoleA required
    options.AddPolicy(PolicyA, policy =>
        {
            policy.AddAuthenticationSchemes(SchemeA)
                  .RequireAuthenticatedUser()
                  .RequireRole(RoleA);
        });
    // UserB required, no scheme specified here so must be specified in [Authorize] attribute if no default
    options.AddPolicy(PolicyB, policy =>
        {
            policy.RequireAuthenticatedUser()
                  .RequireRole(RoleB);
        });
    // UserA or UserB required in RoleA or RoleB
    options.AddPolicy(PolicyAorB, policy =>
        {
            policy.RequireAuthenticatedUser()
                  .AddAuthenticationSchemes(SchemeA, SchemeB)
                  .RequireRole(RoleA, RoleB);
        });
    // UserA,B,C any role
    options.AddPolicy(PolicyAnyRole, policy => {
            policy.RequireAuthenticatedUser()
                  .AddAuthenticationSchemes(SchemeA, SchemeB, SchemeC);
        });
    // UserA and RoleC required
    options.AddPolicy(PolicyUserAandRoleC, policy => {
            policy.AddAuthenticationSchemes(SchemeA)
                  .RequireRole(RoleC);
        });
});

```

> I'm not totally clear on use of `RequireAuthenticatedUser`. If a policy has `RequireRole`, then it isn't needed. The `PolicyAnyRole` that only adds schemes will not work without it.

Later in `Program.cs`, the auth middleware is added to the pipeline to enable authentication and authorization. Remember that middleware is run in the order they are configured so make sure authentication is before authorization.

```csharp
app.UseAuthentication();
app.UseAuthorization();
```

## The Controller

Now that auth is thoroughly configured, we can secure the endpoints in the `AuthTestController`. There is an endpoint to test each policy registered above, as well as one without any security, and one to use the default scheme. The `[Authorize]` attribute secures the endpoints. It can be used at the class level if all endpoints are secured the same way, or at the method level to override the class level. In the sample, I use it on each method since they are all different.

| Path          | Attribute                                                        | Expected Result                                  |
| ------------- | ---------------------------------------------------------------- | ------------------------------------------------ |
| auth          | `[Authorize]`                                                    | 500 if no default policy                         |
| auth/a        | `[Authorize(PolicyA)]`                                           | OK for UserA with role A                         |
| auth/a-and-b  | `[Authorize(PolicyA)][Authorize(PolicyB)]`                       | OK if both role A and B                          |
| auth/a-or-b   | `[Authorize(PolicyAOrB)]`                                        | OK for role A or B                               |
| auth/a-role-c | `[Authorize(PolicyUserAandRoleC)]`                               | Ok for UserA with role C                         |
| auth/any      | `[Authorize(PolicyAnyRole)]`                                     | OK for UserA,B,C,* with any role                 |
| auth/b        | `[Authorize(PolicyB)]`                                           | 500 if no default policy, 200 if default SchemeB, 401 if another scheme |
| auth/b-scheme | `[Authorize(Policy = PolicyB, AuthenticationSchemes = SchemeB)]` | OK for UserB with role B                         |
| auth/none     | None                                                             | OK for all                                       |

## Running the Sample and Tests

To make running and testing the sample easier, there is a `run.ps1` file in the repo. It takes a list of `tasks` for running snippets of PowerShell to run and test the sample. The tests run positive and negative tests against the endpoints. The controller and authentication handler log out what is going on so you can see what code is called.

> For testing the API, I call [Pester](https://pester.dev/) to run tests in `auth.tests.ps1`. I always use it for testing APIs. It is simple, powerful, and can be used in CI -- kicking out standard XML for reporting in Azure DevOps, etc.

For testing without a default authentication scheme, run these commands. Since there is no default, several endpoints will return a 500 and you'll see errors in the output, but the tests expect that and will pass.

```powershell
# in one prompt (this will block)
.\run.ps1 watch

# in a second prompt, all tests should pass
.\run.ps1 test
```

For testing with a default authentication scheme, run these commands. The tests will pass if the default is set to `SchemeA`.

```powershell
# in one prompt (this will block)
 .\run.ps1 watch -DefaultAuthScheme SchemeA

# in a second prompt, all tests should pass
.\run.ps1 testDefault
```

## Default Authentication

By default, the sample uses no default authentication scheme, but one can be passed in via the command line (e.g. `/run.ps1 watch -DefaultAuthScheme SchemeA`).

The `/auth` endpoint only uses `[Authorize]` and `PolicyB` does not specify a scheme so calling them without a default scheme set will get a 500 with this error:

```text
An unhandled exception has occurred while executing the request.
System.InvalidOperationException: No authenticationScheme was specified, and there was no DefaultChallengeScheme found. The default schemes can be set using either AddAuthentication(string defaultScheme) or AddAuthentication(Action<AuthenticationOptions> configureOptions).
```

Setting a default will make those run without 500s.

The schemes are evaluated in the order they are registered, and the if there is a default one, it runs first. Below is the log output calling `/any` with a default scheme of `SchemeC`. Since `/any` uses the `PolicyAnyRole` policy that uses schemes A, B, and C, and the default scheme is set to C, it gets called twice.

```text
>>>> /api/auth/any
SchemeC was not authenticated. Failure message: 'UserZ' was not 'UserC'
SchemeA was not authenticated. Failure message: 'UserZ' was not 'UserA'
SchemeB was not authenticated. Failure message: 'UserZ' was not 'UserB'
SchemeC was not authenticated. Failure message: 'UserZ' was not 'UserC'
```

And without a default scheme, only the explicit schemes are called. C is only called once.

```text
>>>> /api/auth/any
SchemeA was not authenticated. Failure message: 'UserZ' was not 'UserA'
SchemeB was not authenticated. Failure message: 'UserZ' was not 'UserB'
SchemeC was not authenticated. Failure message: 'UserZ' was not 'UserC'
```

## Multiple Authentication Schemes

You may think that once authenticated, authentication stop, but you can see that all schemes are called even when one succeeds. Here `SchemeA` authenticates the user, but B also tries.

```text
>>>> /api/auth/a-and-b
SchemeA was authenticated. Set claims on UserA: name = 'A', role = 'A', role = 'B'
SchemeB was not authenticated. Failure message: 'UserA' was not 'UserB'
```

When multiple schemes' handlers are called, the last one to set a claim on the `ClaimPrincipal` will win. Here's the log when `/any` is called for `UserB` and roles `A,Q`. Only the authentication handler for B matches and sets the `Name` and `Role` claims.

```text
>>>> /api/auth/any
SchemeA was not authenticated. Failure message: 'UserB' was not 'UserA'
SchemeB was authenticated. Set claims on UserB: name = 'B', role = 'A', role = 'Q'
SchemeC was not authenticated. Failure message: 'UserB' was not 'UserC'
GetAuthAnyRole
    Name claim: B
    Role: A
    Role: Q
```

And a similar call using `User*`, who authenticates with _all_ authentication handlers. SchemeA will set `Name` to A, then B overwrites it to B, and finally, C wins. This is probably not a real-life scenario where multiple schemes would be used to authenticate the same user, but it's good to keep in mind.

```text
>>>> /api/auth/any
SchemeA was authenticated. Set claims on User*: name = 'A', role = 'A', role = 'Q'
SchemeB was authenticated. Set claims on User*: name = 'B', role = 'A', role = 'Q'
SchemeC was authenticated. Set claims on User*: name = 'C', role = 'A', role = 'Q'
GetAuthAnyRole
    Name claim: C
    Role: A
    Role: Q
    Role: A
    Role: Q
    Role: A
    Role: Q
```

## Summary

Writing this sample code and post, I have a better understanding of how authentication and authorization work in ASP.NET Core. I hope you do too.

## Links

- [Source code](https://github.com/Seekatar/ioptions-logger-test)
- [MS: Overview of ASP.NET Core authentication]([Title](https://learn.microsoft.com/en-us/aspnet/core/security/authentication))
- [MS: Introduction to authorization in ASP.NET Core](https://learn.microsoft.com/en-us/aspnet/core/security/authorization/introduction)
- [MS: AuthenticationHandler](https://learn.microsoft.com/en-us/dotnet/api/microsoft.aspnetcore.authentication.authenticationhandler-1?view%253Daspnetcore-7.0)
