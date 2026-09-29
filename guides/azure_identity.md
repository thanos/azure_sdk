# Azure Identity with AzureSDK

AzureSDK separates **request authorization** (Shared Key, SAS) from **token acquisition** (Entra ID / OAuth).

## Request credentials

```elixir
shared_key =
  AzureSDK.Identity.SharedKeyCredential.new(account, key)

sas =
  AzureSDK.Identity.SASCredential.new("sv=...&sig=...")
```

These implement `AzureSDK.Identity.Credential.authorize_request/2`.

## Token credentials

```elixir
credential =
  AzureSDK.Identity.ClientSecretCredential.new(
    tenant_id: System.fetch_env!("AZURE_TENANT_ID"),
    client_id: System.fetch_env!("AZURE_CLIENT_ID"),
    client_secret: System.fetch_env!("AZURE_CLIENT_SECRET")
  )

client =
  AzureSDK.Storage.Client.new(
    account: "myaccount",
    credential: credential
  )
```

The pipeline:

1. Calls `TokenCache.fetch/3` (coalesced, expiry-aware)
2. Applies `Authorization: Bearer …` via `Pipeline.Bearer`
3. On HTTP 401, invalidates the cache and retries authorization once

### DefaultAzureCredential

```elixir
credential = AzureSDK.Identity.DefaultAzureCredential.new()
```

Tries Environment → Workload Identity → Managed Identity.

Environment variables:

| Variable | Purpose |
|----------|---------|
| `AZURE_TENANT_ID` | Directory (tenant) id |
| `AZURE_CLIENT_ID` | App registration / managed identity client id |
| `AZURE_CLIENT_SECRET` | Client secret |
| `AZURE_FEDERATED_TOKEN_FILE` | Workload identity token path |
| `AZURE_AUTHORITY_HOST` | Optional login host override |

### Managed identity

```elixir
AzureSDK.Identity.ManagedIdentityCredential.new()
AzureSDK.Identity.ManagedIdentityCredential.new(client_id: "user-assigned-id")
```

## Token cache telemetry

- `[:azure_sdk, :auth, :token_cache, :hit]`
- `[:azure_sdk, :auth, :token_cache, :miss]`
- `[:azure_sdk, :auth, :token, :acquire]` — duration of `get_token/3`
- `[:azure_sdk, :auth, :sign]` — `scheme: :bearer` or `:shared_key`

Never attach handlers that log token values.

## Scopes

Default storage scope: `https://storage.azure.com/.default`.

Override per request:

```elixir
Pipeline.run(core_client, request, scopes: ["https://management.azure.com/.default"])
```

## Related

- `plans/identity-architecture.md`
- `livebooks/authentication.livemd`
