# AzureSDK Multi-Service Architecture

AzureSDK v0.1.0 ships Blob Storage, but the codebase is organized as a **platform SDK** from day one. Every module namespace, client struct, and pipeline stage is designed so that Queue, Table, Management, and BEAM integrations slot in without refactoring the foundation.

## Design Goals

1. **Mirror Microsoft Azure SDK separation** — identity, data plane, management plane, and shared core are distinct layers.
2. **Embrace BEAM strengths** — telemetry, supervision, streaming, and future Broadway/Flow integrations are first-class design inputs.
3. **No hidden state** — clients are plain structs; credentials and retry policies are explicit configuration.
4. **Service-agnostic pipeline** — `AzureSDK.Core.Pipeline` knows nothing about blobs, queues, or ARM resources.

## Layer Diagram

```
AzureSDK
├── Identity Plane          AzureSDK.Identity.*
│   ├── SharedKey / SAS     request credentials
│   ├── TokenCredentials    ClientSecret, ManagedIdentity, WorkloadIdentity, …
│   └── TokenCache          supervised OTP cache
├── Data Plane              AzureSDK.Storage.*
│   ├── Blob / Container    implemented
│   └── Queue/Table/…       namespaces reserved
├── Management Plane        AzureSDK.Management.* (reserved v0.6)
├── Core Platform           AzureSDK.Core.*
│   ├── Pipeline            authorize → retry → transport
│   ├── Request/Response    service-agnostic HTTP model
│   ├── Retry               jitter, Retry-After, idempotency
│   ├── Telemetry           :telemetry events
│   ├── Error               standardized errors
│   └── Xml.*               internal parsers only
├── Pipeline Middleware     AzureSDK.Pipeline.*
│   ├── SharedKey / SAS / Bearer
│   └── Telemetry
└── Integrations            reserved namespaces
```

## Request Lifecycle

Every service operation follows the same path:

```
Service Module (e.g. Blob.upload/4)
    → builds AzureSDK.Core.Request
    → AzureSDK.Core.Pipeline.run/3
        → Telemetry.span/2 (duration measurement)
        → authorize/2 (SharedKey | SAS | TokenCache+Bearer)
        → Pipeline.Telemetry.apply/2 (emit [:azure_sdk, :request, :attempt])
        → Req.request/1 (transport)
        → Retry on 408, 429, 5xx (and idempotent transport errors)
    → {:ok, Response} | {:error, Error}
```

Service modules emit **operation-level** telemetry (`[:azure_sdk, :blob, :put]`) before calling the pipeline. The pipeline emits **request-level** telemetry (`[:azure_sdk, :request, :start | :stop | :attempt]`); `:stop` carries the span duration.

## Client Hierarchy

Two client layers keep service configuration separate from transport configuration:

| Layer | Module | Responsibility |
|-------|--------|----------------|
| Service | `AzureSDK.Storage.Client` | Account, endpoint, API version, path-style detection |
| Core | `AzureSDK.Core.Client` | Credential, retry, Req options, endpoint for pipeline |

`Storage.Client.to_core_client/1` bridges the two. Management clients will follow the same pattern with subscription-scoped configuration.

## Namespace Reservation

v0.1.0 includes stub modules for Queue, Table, FileShare, DataLake, and all Management submodules. This prevents API churn when those services land and signals intent to contributors and downstream consumers.

## Emulator Support

`Storage.Client.path_style?/1` detects path-style endpoints — those whose path ends with the account name (e.g. Azurite at `http://127.0.0.1:10000/devstoreaccount1`) — and can be forced with the `:path_style` client option. Signing metadata passes `path_style: true` to `SharedKey`, which applies the **double account name** canonicalized resource path required by path-style emulators. Host-style endpoints (public cloud, sovereign clouds, custom domains) sign with a single account prefix.

## Error Contract

All public APIs return `{:ok, result}` or `{:error, %AzureSDK.Error{}}`. XML error bodies are parsed internally; consumers never see raw Azure XML.

## Testing Architecture

- **Unit tests** — signing canonicalization, XML parsing, retry policy
- **Property tests** — StreamData for string-to-sign invariants
- **Integration tests** — Azurite via `AzureSDK.AzuriteCase`, no cloud account required

## Key Architectural Constraints

1. Blob modules must not implement signing logic — that belongs in `AzureSDK.Pipeline.SharedKey`.
2. XML must not leak past `AzureSDK.Core.Xml.*` parsers.
3. New credentials implement `AzureSDK.Identity.Credential` behaviour and plug into `Pipeline.sign/2`.
4. Transport stays on Req; do not bypass the pipeline for "quick" HTTP calls.

## Related Documents

- `pipeline-design.md` — middleware chain details
- `identity-architecture.md` — credential plane and OAuth roadmap
- `data-plane-vs-management-plane.md` — ARM vs storage service APIs
- `README.md` (Roadmap) — version-by-version delivery plan
