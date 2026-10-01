# Azurex Review - Comparison with AzureSDK

[Azurex](https://github.com/treasure-data/azurex) is the established Elixir library for Azure Storage. AzureSDK is designed as a **platform SDK** that supersedes Azurex's scope over multiple releases. This document compares architectures and guides migration planning.

## Summary

| Dimension | Azurex | AzureSDK v0.4.0 |
|-----------|--------|-----------------|
| Scope | Primarily Blob Storage | Platform SDK (Blob + Queue; Table/Mgmt later) |
| HTTP client | HTTPoison / Hackney | Req → Finch → Mint |
| Auth | Inline signing in storage modules | Identity plane + pipeline middleware (SharedKey, SAS, Entra TokenCredentials) |
| Telemetry | None built-in | `:telemetry` on every operation and request |
| Error type | Various tuples / exceptions | `%AzureSDK.Error{}` consistently |
| Testing | Cloud or manual | Azurite-first integration suite |
| Management plane | Not supported | Namespace reserved (v0.6.0) |
| Streaming | Limited | Bounded-memory block upload + Range download streams |
| Conditions / leases | Limited | `Conditions` + blob leases |
| Lazy listing | Varies | `list_*_page` / `list_*_stream` (+ eager helpers) |
| SAS | Generation + consumption | Consume (`SASCredential`) and generate (`Storage.Sas` for Blob) |
| Queue Storage | Limited/absent | `Storage.Queue` + `Queue.Message` |
| API version | Older defaults | `2024-11-04` default (`ServiceVersion`) |

## Architectural Differences

### Monolith vs Layers

Azurex couples HTTP, signing, and blob operations in a relatively flat module structure. Configuration and auth logic live close to the API calls. This works for a single-service library but makes it hard to add Queue, Table, or ARM without duplicating signing and retry logic.

AzureSDK separates concerns:

```
AzureSDK.Identity.*        → credentials (SharedKey, SAS, Entra)
AzureSDK.Pipeline.*        → signing / Bearer middleware
AzureSDK.Core.Pipeline     → retry, telemetry, transport
AzureSDK.Storage.Blob      → blob operations
AzureSDK.Storage.Queue     → queue + message operations
AzureSDK.Storage.Sas       → SAS generation (Shared Key + user-delegation)
```

Queue Storage reuses the same pipeline; callers use `Storage.Client.new(..., service: :queue)`.

### Authentication

Azurex typically accepts account name and key at call sites or via application config. AzureSDK requires an explicit credential struct:

```elixir
credential = AzureSDK.Identity.SharedKeyCredential.new(account, key)
client = AzureSDK.Storage.Client.new(account: account, credential: credential)
```

SAS tokens are first-class via `SASCredential` (consumption) and `AzureSDK.Storage.Sas` (generation of blob/container service SAS and user-delegation SAS). Entra auth ships as `TokenCredential` implementations with a supervised `TokenCache` and Bearer pipeline support.

### HTTP Stack

Azurex depends on HTTPoison (Hackney). AzureSDK uses Req, which provides a composable middleware model closer to Azure Core policies. Req defaults to Finch (HTTP/2, connection pooling) with Mint underneath. Users can pass custom `req_options` for timeouts, proxies, or alternative adapters.

### Error Handling

Azurex returns mixed error shapes depending on the operation. AzureSDK standardizes on `{:error, %AzureSDK.Error{status:, code:, message:, request_id:, service:}}`, parsing Azure XML error bodies automatically.

### Observability

Azurex has no built-in telemetry. AzureSDK emits events like `[:azure_sdk, :blob, :put]`, `[:azure_sdk, :queue, :put_message]`, and `[:azure_sdk, :request, :stop]`.

## Feature Parity (v0.4.0)

| Feature | Azurex | AzureSDK |
|---------|--------|----------|
| Upload blob | Yes | Yes (`upload`, `upload_stream`) |
| Download blob | Yes | Yes (`download`, `download_stream`, optional `:range`) |
| Delete blob | Yes | Yes |
| Container CRUD | Yes | Yes (create, delete, list / `list_page` / `list_stream`) |
| List blobs | Yes | Yes (eager + `list_blobs_page` / `list_blobs_stream`) |
| Blob metadata | Partial | Yes (get + set) |
| Block blobs | Yes | Yes (`Blob.Block`; streaming uses them) |
| Conditions / leases | Varies | Yes (`Conditions`, `Blob.Lease`) |
| Page/append blobs | Some support | Block blob focus |
| SAS consumption | Yes | Yes (`SASCredential`) |
| SAS generation | Yes | Yes (Blob/container; Queue SAS later) |
| Entra / OAuth | Limited/absent | Yes (v0.2.0+) |
| Queue CRUD / messages | Limited/absent | Yes (`Queue`, `Queue.Message`) |
| Table | Limited/absent | Planned v0.5 |

## Azurite Compatibility

Path-style double-account Shared Key signing is handled when `path_style: true`. Blob tests use `http://127.0.0.1:10000/devstoreaccount1`; Queue tests use port **10001**.

## Migration Considerations

1. **Replace config-based keys** with explicit credential structs.
2. **Wrap client creation** - one `Storage.Client` per account/service endpoint.
3. **Update error handling** - pattern match on `%AzureSDK.Error{}`.
4. **Add telemetry handlers** for production.
5. **Remove HTTPoison** if it was only used for Azurex.
6. **Map Queue ops** to `AzureSDK.Storage.Queue` / `Queue.Message`.

See `guides/migrating_from_azurex.md`.

## When to Stay on Azurex

- You need a mature library today with minimal API surface change.
- Your usage is limited to basic blob CRUD with no telemetry, Entra, or Queue needs.

## When to Adopt AzureSDK

- Starting a new project or major refactor.
- You need telemetry, standardized errors, or Azurite-first CI.
- You need production streaming, conditions/leases, lazy listing, SAS generation, or Queue Storage.
- You need Entra / managed identity auth.
- You plan to use Table or ARM APIs as they ship.

## Conclusion

Through v0.4.0, AzureSDK covers production Blob and Queue Storage plus Entra identity from v0.2.0. Table, ARM, and BEAM integrations follow without breaking that foundation.
