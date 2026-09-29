# Azurex Review — Comparison with AzureSDK

[Azurex](https://github.com/treasure-data/azurex) is the established Elixir library for Azure Storage. AzureSDK is designed as a **platform SDK** that supersedes Azurex's scope over multiple releases. This document compares architectures and guides migration planning.

## Summary

| Dimension | Azurex | AzureSDK v0.1.0 |
|-----------|--------|----------------|
| Scope | Primarily Blob Storage | Platform SDK (Blob now, Queue/Table/Mgmt later) |
| HTTP client | HTTPoison / Hackney | Req → Finch → Mint |
| Auth | Inline signing in storage modules | Identity plane + pipeline middleware |
| Telemetry | None built-in | `:telemetry` on every operation and request |
| Error type | Various tuples / exceptions | `%AzureSDK.Error{}` consistently |
| Testing | Cloud or manual | Azurite-first integration suite |
| Management plane | Not supported | Namespace reserved (v0.5.0) |
| Streaming | Limited | `upload_stream`, `download_stream` |
| API version | Older defaults | `2024-11-04` default |

## Architectural Differences

### Monolith vs Layers

Azurex couples HTTP, signing, and blob operations in a relatively flat module structure. Configuration and auth logic live close to the API calls. This works for a single-service library but makes it hard to add Queue, Table, or ARM without duplicating signing and retry logic.

AzureSDK separates concerns:

```
AzureSDK.Identity.*     → credentials
AzureSDK.Pipeline.*     → signing middleware
AzureSDK.Core.Pipeline  → retry, telemetry, transport
AzureSDK.Storage.Blob   → blob operations only
```

Adding Queue Storage in v0.3.0 means a new `AzureSDK.Storage.Queue` module reusing the same pipeline — not copying auth code.

### Authentication

Azurex typically accepts account name and key at call sites or via application config. AzureSDK requires an explicit credential struct:

```elixir
credential = AzureSDK.Identity.SharedKeyCredential.new(account, key)
client = AzureSDK.Storage.Client.new(account: account, credential: credential)
```

SAS tokens are first-class via `SASCredential`, parsed from query strings or maps. This matches Microsoft's credential-centric design and prepares for OAuth tokens in v0.2.0 without API redesign.

### HTTP Stack

Azurex depends on HTTPoison (Hackney). AzureSDK uses Req, which provides a composable middleware model closer to Azure Core policies. Req defaults to Finch (HTTP/2, connection pooling) with Mint underneath. Users can pass custom `req_options` for timeouts, proxies, or alternative adapters.

### Error Handling

Azurex returns mixed error shapes depending on the operation. AzureSDK standardizes on `{:error, %AzureSDK.Error{status:, code:, message:, request_id:, service:}}`, parsing Azure XML error bodies automatically. This enables generic error handlers and telemetry correlation.

### Observability

Azurex has no built-in telemetry. AzureSDK emits events like `[:azure_sdk, :blob, :put]` and `[:azure_sdk, :request, :stop]` with duration measurements. Operators can integrate with LiveDashboard, OpenTelemetry bridges, or custom logging without modifying library code.

## Feature Parity (v0.1.0)

| Feature | Azurex | AzureSDK |
|---------|--------|---------|
| Upload blob | ✓ | ✓ (`upload`, `upload_stream`) |
| Download blob | ✓ | ✓ (`download`, `download_stream`) |
| Delete blob | ✓ | ✓ |
| Container CRUD | ✓ | ✓ (create, delete, list) |
| List blobs | ✓ | ✓ |
| Blob metadata | Partial | ✓ (get + set) |
| Block blobs | ✓ | ✓ (default blob type) |
| Page/append blobs | Some support | Block blob focus in v0.1.0 |
| SAS generation | ✓ | SAS credential consumption (generation planned) |
| Queue/Table | Limited/absent | Stubs, planned v0.3–0.4 |

## Azurite Compatibility

Both libraries support local development with Azurite. AzureSDK handles the path-style **double account name** signing quirk explicitly in `SharedKey.canonicalized_resource/4` when `path_style: true`. Integration tests use `AzureSDK.AzuriteCase` with endpoint `http://127.0.0.1:10000/devstoreaccount1`.

## Migration Considerations

1. **Replace config-based keys** with explicit `SharedKeyCredential` structs.
2. **Wrap client creation** — one `Storage.Client` per account, pass to all operations.
3. **Update error handling** — pattern match on `%AzureSDK.Error{}` instead of raw HTTP errors.
4. **Add telemetry handlers** — optional but recommended for production.
5. **Update HTTP-related deps** — remove HTTPoison if it was only used for Azurex.

See `guides/migrating_from_azurex.md` for a step-by-step migration guide.

## When to Stay on Azurex

- You need a mature library today with minimal API surface change.
- Your usage is limited to basic blob CRUD with no telemetry or management plane needs.

## When to Adopt AzureSDK

- Starting a new project or major refactor.
- You need telemetry, standardized errors, or Azurite-first CI.
- You plan to use Queue, Table, or ARM APIs as they ship.
- You want BEAM integrations (Broadway, Explorer) in the future.

## Conclusion

Azurex proved Elixir developers need Azure Storage access. AzureSDK builds on that lesson with a platform architecture modeled after Microsoft's SDK design, Req-based transport, and BEAM-native observability. v0.1.0 covers core blob scenarios; subsequent releases expand scope without breaking the foundation.
