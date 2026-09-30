# Azurex Review - Comparison with AzureSDK

[Azurex](https://github.com/treasure-data/azurex) is the established Elixir library for Azure Storage. AzureSDK is designed as a **platform SDK** that supersedes Azurex's scope over multiple releases. This document compares architectures and guides migration planning.

## Summary

| Dimension | Azurex | AzureSDK v0.3.0 |
|-----------|--------|-----------------|
| Scope | Primarily Blob Storage | Platform SDK (Blob now; Queue/Table/Mgmt later) |
| HTTP client | HTTPoison / Hackney | Req → Finch → Mint |
| Auth | Inline signing in storage modules | Identity plane + pipeline middleware (SharedKey, SAS, Entra TokenCredentials) |
| Telemetry | None built-in | `:telemetry` on every operation and request |
| Error type | Various tuples / exceptions | `%AzureSDK.Error{}` consistently |
| Testing | Cloud or manual | Azurite-first integration suite |
| Management plane | Not supported | Namespace reserved (v0.6.0) |
| Streaming | Limited | Bounded-memory block upload + Range download streams |
| Conditions / leases | Limited | `Conditions` + blob leases |
| Lazy listing | Varies | `list_*_page` / `list_*_stream` (+ eager helpers) |
| SAS | Generation + consumption | Consume (`SASCredential`) and generate (`Storage.Sas`) |
| API version | Older defaults | `2024-11-04` default (`ServiceVersion`) |

## Architectural Differences

### Monolith vs Layers

Azurex couples HTTP, signing, and blob operations in a relatively flat module structure. Configuration and auth logic live close to the API calls. This works for a single-service library but makes it hard to add Queue, Table, or ARM without duplicating signing and retry logic.

AzureSDK separates concerns:

```
AzureSDK.Identity.*     → credentials (SharedKey, SAS, Entra)
AzureSDK.Pipeline.*     → signing / Bearer middleware
AzureSDK.Core.Pipeline  → retry, telemetry, transport
AzureSDK.Storage.Blob   → blob operations only
AzureSDK.Storage.Sas    → SAS generation (Shared Key + user-delegation)
```

Adding Queue Storage in v0.4.0 means a new `AzureSDK.Storage.Queue` module reusing the same pipeline - not copying auth code.

### Authentication

Azurex typically accepts account name and key at call sites or via application config. AzureSDK requires an explicit credential struct:

```elixir
credential = AzureSDK.Identity.SharedKeyCredential.new(account, key)
client = AzureSDK.Storage.Client.new(account: account, credential: credential)
```

SAS tokens are first-class via `SASCredential` (consumption) and `AzureSDK.Storage.Sas` (generation of blob/container service SAS and user-delegation SAS). Entra auth ships as `TokenCredential` implementations (`ClientSecretCredential`, `ManagedIdentityCredential`, `WorkloadIdentityCredential`, `EnvironmentCredential`, `DefaultAzureCredential`) with a supervised `TokenCache` and Bearer pipeline support.

### HTTP Stack

Azurex depends on HTTPoison (Hackney). AzureSDK uses Req, which provides a composable middleware model closer to Azure Core policies. Req defaults to Finch (HTTP/2, connection pooling) with Mint underneath. Users can pass custom `req_options` for timeouts, proxies, or alternative adapters.

### Error Handling

Azurex returns mixed error shapes depending on the operation. AzureSDK standardizes on `{:error, %AzureSDK.Error{status:, code:, message:, request_id:, service:}}`, parsing Azure XML error bodies automatically. This enables generic error handlers and telemetry correlation.

### Observability

Azurex has no built-in telemetry. AzureSDK emits events like `[:azure_sdk, :blob, :put]` and `[:azure_sdk, :request, :stop]` with duration measurements (streaming uploads include `streaming: true`). Operators can integrate with LiveDashboard, OpenTelemetry bridges, or custom logging without modifying library code.

## Feature Parity (v0.3.0)

| Feature | Azurex | AzureSDK |
|---------|--------|----------|
| Upload blob | Yes | Yes (`upload`, `upload_stream`) |
| Download blob | Yes | Yes (`download`, `download_stream`, optional `:range`) |
| Delete blob | Yes | Yes |
| Container CRUD | Yes | Yes (create, delete, list / `list_page` / `list_stream`) |
| List blobs | Yes | Yes (eager + `list_blobs_page` / `list_blobs_stream`) |
| Blob metadata | Partial | Yes (get + set) |
| Block blobs | Yes | Yes (`Blob.Block.put_block` / `put_block_list`; streaming uses them) |
| Conditions | Varies | Yes (`If-*`, `:lease_id` via `Storage.Conditions`) |
| Blob leases | Varies | Yes (acquire / renew / change / release / break) |
| Page/append blobs | Some support | Block blob focus (out of scope through v0.3.0) |
| SAS consumption | Yes | Yes (`SASCredential`) |
| SAS generation | Yes | Yes (`Storage.Sas` Shared Key + user-delegation) |
| Entra / OAuth | Limited/absent | Yes (v0.2.0+) |
| Queue/Table | Limited/absent | Planned v0.4 / v0.5 |

## Azurite Compatibility

Both libraries support local development with Azurite. AzureSDK handles the path-style **double account name** signing quirk explicitly in `SharedKey.canonicalized_resource/4` when `path_style: true`. Integration tests use `AzureSDK.AzuriteCase` with endpoint `http://127.0.0.1:10000/devstoreaccount1`. The Azurite suite covers streaming round trips, the full lease lifecycle, conditional writes, multi-page listing, and Shared Key SAS generation (a generated SAS must authorize a real download, and a write-only SAS must be refused). Service SAS signatures are also checked against reference values from the Azure SDK for Python. User-delegation SAS needs Entra ID, which Azurite does not provide, so it is tested against the documented string-to-sign format only.

## Migration Considerations

1. **Replace config-based keys** with explicit `SharedKeyCredential` (or Entra credentials) structs.
2. **Wrap client creation** - one `Storage.Client` per account, pass to all operations.
3. **Update error handling** - pattern match on `%AzureSDK.Error{}` instead of raw HTTP errors.
4. **Add telemetry handlers** - optional but recommended for production.
5. **Update HTTP-related deps** - remove HTTPoison if it was only used for Azurex.
6. **Map SAS generation** from Azurex helpers to `AzureSDK.Storage.Sas.sign_blob/2` / `sign_container/2` (and user-delegation helpers when using TokenCredentials).

See `guides/migrating_from_azurex.md` for a step-by-step migration guide.

## When to Stay on Azurex

- You need a mature library today with minimal API surface change.
- Your usage is limited to basic blob CRUD with no telemetry, Entra, or management-plane needs.

## When to Adopt AzureSDK

- Starting a new project or major refactor.
- You need telemetry, standardized errors, or Azurite-first CI.
- You need production streaming, conditions/leases, lazy listing, or SAS generation.
- You need Entra / managed identity auth.
- You plan to use Queue, Table, or ARM APIs as they ship.
- You want BEAM integrations (Broadway, Explorer) in the future.

## Conclusion

Azurex proved Elixir developers need Azure Storage access. AzureSDK builds on that lesson with a platform architecture modeled after Microsoft's SDK design, Req-based transport, and BEAM-native observability. Through v0.3.0, AzureSDK covers core and production Blob scenarios (streaming, blocks, conditions, leases, lazy listing, SAS generation) plus Entra identity from v0.2.0; later releases expand into Queue, Table, and ARM without breaking that foundation.
