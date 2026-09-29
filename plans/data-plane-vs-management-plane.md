# Data Plane vs Management Plane

Azure exposes two API surfaces. AzureSDK mirrors this in module structure, client design, and credentials.

## Definitions

| Plane | Purpose | Endpoint | Auth | Example |
|-------|---------|----------|------|---------|
| **Data** | Read/write data | `{account}.blob.core.windows.net` | Shared Key, SAS, AAD | Upload blob |
| **Management** | Provision resources | `management.azure.com` | OAuth2 Bearer | Create storage account |

## AzureSDK Module Mapping

### Data Plane - `AzureSDK.Storage.*`

| Module | Status |
|--------|--------|
| `Blob`, `Container` | v0.1.0 implemented |
| `Queue`, `Table`, `FileShare`, `DataLake` | Stubs |

`Storage.Client` config: `account`, `endpoint`, `api_version` (default `2024-11-04`).

### Management Plane - `AzureSDK.Management.*`

| Module | Status |
|--------|--------|
| `Client`, `StorageAccount`, `Policy`, `Network`, `Replication` | Stubs (v0.6.0) |

`Management.Client` config: `subscription_id`, `endpoint`, `api_version`.

## Authentication

**Data (v0.1.0):** `SharedKeyCredential` → HMAC via `Pipeline.SharedKey`; `SASCredential` → query params.

**Management (v0.6.0):** OAuth2 only via `ClientSecretCredential` or `ManagedIdentityCredential` (v0.2.0). Scope: `https://management.azure.com/.default`.

## Request Differences

| Aspect | Data | Management |
|--------|------|------------|
| Body | XML (Blob) | JSON |
| Errors | XML `<Error>` | JSON `error` object |
| Async ops | Rare | Common (LRO) |
| Path | `/{container}/{blob}` | `/subscriptions/.../providers/...` |

`Core.Xml.Error` handles data plane. `Core.Json.Error` planned for management.

## Client Examples

```elixir
# Data plane (v0.1.0)
storage = Storage.Client.new(account: "myaccount", credential: shared_key)
Blob.upload(storage, "data", "file.bin", content)

# Management (future)
mgmt = Management.Client.new(subscription_id: "sub", credential: oauth)
Management.StorageAccount.create(mgmt, "rg", "newaccount", location: "eastus")
```

## Pipeline Reuse

Both planes produce `Core.Request` and call `Pipeline.run/3`. Signing is credential-driven, not plane-driven.

Management additions (v0.6.0): `Pipeline.LRO` polling, JSON bodies, ARM URL builder.

## Why One SDK

Microsoft ships separate data and mgmt packages sharing `azure-core` and `azure-identity`. AzureSDK does the same at the module level with shared pipeline, telemetry, and errors.

## Related Documents

- `identity-architecture.md` - credentials per plane
- `guides/management_plane_design.md` - ARM patterns
- `README.md` (Roadmap) - v0.6.0 timeline
