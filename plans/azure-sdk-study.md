# Azure SDK Study — Findings

Before implementing AzureSDK v0.1.0, we studied Microsoft's official Azure SDK ecosystem. This document captures architectural patterns worth adopting, gaps where the BEAM can do better, and concrete decisions reflected in the codebase.

## Sources Reviewed

- [Azure SDK Design Guidelines](https://azure.github.io/azure-sdk/general_introduction.html)
- `azure-core` — HTTP pipeline, policies, transport abstraction
- `azure-identity` — credential types, token caching, chained credentials
- `azure-storage-blob` — data plane client design, streaming APIs
- `azure-mgmt-storage` — management plane, ARM REST patterns
- Azure Storage REST API documentation (Shared Key auth, API versions)

## What Microsoft Does Well

### Client-Centric Design

Every service exposes a `*Client` class constructed with endpoint, credential, and options. Operations are methods on the client or free functions that accept a client. AzureSDK mirrors this with `AzureSDK.Storage.Client.new/1` and operation modules (`Blob`, `Container`).

### Pipeline Policies

Azure Core chains **policies** (retry, redirect, logging, authentication) around a transport. Each policy transforms a request or response. AzureSDK implements an equivalent chain in `AzureSDK.Core.Pipeline`:

```
Credential → Signing → Retry → Telemetry → Transport (Req)
```

Policies are modules, not callbacks, keeping the chain testable and explicit.

### Credential Abstraction

`TokenCredential` is a protocol in many languages; in Python it's an ABC. AzureSDK uses an Elixir **behaviour** (`AzureSDK.Identity.Credential`) with `sign_request/2`. Shared Key, SAS, and future OAuth credentials all implement the same callback.

### API Versioning

Storage services pin an `x-ms-version` header. AzureSDK defaults to `2024-11-04` on `Storage.Client` and passes it through signing metadata.

### No XML in Public APIs

Official SDKs deserialize XML internally and return typed objects. AzureSDK's `ListContainers` and `ListBlobs` parsers live in `AzureSDK.Core.Xml.*` and return maps/structs.

## Patterns We Adopted Directly

| Microsoft Pattern | AzureSDK Implementation |
|-------------------|------------------------|
| `AzureCore` pipeline | `AzureSDK.Core.Pipeline` |
| `AzureKeyCredential` | `SharedKeyCredential` |
| `AzureSasCredential` | `SASCredential` |
| Retry policy with backoff | `AzureSDK.Core.Retry` |
| Structured errors | `AzureSDK.Error` with status, code, request_id |
| Client options bag | `req_options` keyword on client struct |

## Where We Improve on Microsoft

### Telemetry as a First-Class Pipeline Stage

Official SDKs support OpenTelemetry, but it's optional and inconsistent across languages. AzureSDK emits `:telemetry` events on every request, operation, sign, and retry. BEAM operators can attach handlers without code changes.

### No Hidden Process State

Python and .NET SDKs may cache tokens in module-level or client-internal state. AzureSDK clients are plain structs. Token caching (v0.2.0) will be an explicit supervised process (`TokenCache`), not an implicit side effect.

### OTP-Native Retry

Retry backoff uses `Process.sleep/1` with telemetry emission. Future versions may integrate with `Retry` library patterns or circuit breakers under supervision.

### BEAM Integrations

Microsoft cannot ship Broadway, Flow, Explorer, or Nx integrations in the official SDK. AzureSDK reserves `AzureSDK.Integrations.*` namespaces for v0.6.0.

### Azurite-First Development

Microsoft docs assume cloud accounts. AzureSDK tests against Azurite with path-style endpoint signing baked into `SharedKey.canonicalized_resource/4`.

## Signing Study Notes

Azure Storage Shared Key signing requires:

1. Canonicalized `x-ms-*` headers (lowercase, sorted, newline-separated)
2. Canonicalized resource path including account name and sorted query string
3. HMAC-SHA256 over a newline-joined string-to-sign
4. Empty `Content-Length: 0` treated as blank in string-to-sign

Azurite path-style endpoints require **double account prefix**: `/account/account/container/blob` instead of `/account/container/blob`. This is implemented when `metadata.path_style` is true.

## Management Plane Observations

ARM APIs use Bearer tokens (OAuth2), JSON bodies, and long-running operations (LROs). They share the pipeline concept but need different signing (no Shared Key) and polling middleware. The `AzureSDK.Management.Client` stub documents this future split.

## Decisions Deferred

| Topic | Decision | Target Version |
|-------|----------|----------------|
| OAuth2 / AAD tokens | `ClientSecretCredential`, `ManagedIdentityCredential` | v0.2.0 |
| DefaultAzureCredential chain | Credential resolver with ordered fallbacks | v0.2.0 |
| LRO polling middleware | Management plane operation polling | v0.5.0 |
| Req vs custom Finch pool | Req with configurable `req_options` | v0.1.0 (done) |

## Conclusion

Microsoft's SDK architecture is the right mental model: clients, credentials, pipelines, and service modules. AzureSDK adopts the structure and improves on observability, OTP integration, and BEAM-native data processing — capabilities no official SDK can match.
