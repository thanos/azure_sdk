# Changelog

## v0.2.0 - 2026-09-29

### Breaking

- `AzureSDK.Identity.Credential` now requires `authorize_request/2` returning
  `{:ok, request} | {:error, error}` (replaces infallible `sign_request/2`)
- Entra credentials implement `TokenCredential.get_token/3` instead of signing directly
- Retry policy defaults include `jitter: true` and `max_retry_after_ms: 60_000`;
  transport errors and HTTP 408/500/502/504 retry only for idempotent requests
  (429 and 503 are always retried)
- `DefaultAzureCredential` chain is Environment → Managed Identity (Environment
  already covers workload identity) and stops at the first error that is not
  `CredentialUnavailable`
- `ManagedIdentityCredential.get_token/3` requires exactly one scope
- The reserved management client module is `@moduledoc false` and no longer exports `t/0`
- Empty future-service modules are `@moduledoc false` (hidden from Hexdocs)

### Added

- `TokenCredential`, `AccessToken`, `Pipeline.Bearer`
- `ClientSecretCredential`, `ManagedIdentityCredential`, `WorkloadIdentityCredential`
- `EnvironmentCredential`, `DefaultAzureCredential`
- Supervised `TokenCache` with expiry buffer and acquire coalescing
- `AzureSDK.Application` OTP application
- Retry: `Retry-After` / `x-ms-retry-after-ms`, full jitter, idempotent transport classification, 401 token refresh-once
- `AzureSDK.Storage.ServiceVersion`
- Guide `guides/azure_identity.md`; updated authentication Livebook
- Architecture docs under `plans/`

### Changed

- Pipeline authorization is fallible and does not HTTP-retry auth failures
- Telemetry: `[:azure_sdk, :auth, :token_cache, :hit | :miss]`, `[:azure_sdk, :auth, :token, :acquire]`
- Roadmap: Identity → Production Blob → Queue → Table → ARM → BEAM

### Fixed

- `TokenCache` no longer hangs a cache key when a credential raises or its
  acquiring process exits; waiters receive `TokenAcquisitionFailed`. `clear/1`
  replies to pending waiters, and expired tokens are pruned
- `DefaultAzureCredential` cache keys include the chain's identities, so
  different chains no longer share tokens
- Credential and `AccessToken` structs hide secrets from `inspect/2`
- `SharedKeyCredential.authorize_request/2` returns `InvalidCredential` for a
  non-Base64 key instead of raising
- `Retry-After` is honored beyond `max_delay_ms`, up to `max_retry_after_ms`
- IMDS requests set a 1s connect timeout so an unreachable endpoint fails fast

## v0.1.0 - 2026-06-12

### Added

- Multi-service architecture with Identity, Data Plane, Management, and Platform layers
- `AzureSDK.Core.Pipeline` - reusable Req-based request pipeline with retry and telemetry
- Identity plane: `SharedKeyCredential`, `SASCredential`, credential behaviour
- Blob Storage: upload, download, delete, metadata, listing, buffered stream helpers
- Container management: create, delete, list, list blobs, metadata
- Standardized `AzureSDK.Error` struct
- XML parsers hidden behind public structs and maps
- Azurite integration tests and Docker Compose environment
- Architecture plans, educational guides, and Livebooks
- GitHub Actions CI: format, Credo, Doctor, Sobelow, Dialyzer, test matrix, docs

### Design stubs (documented, not implemented)

- OAuth credentials (Client Secret, Managed Identity, DefaultAzureCredential)
- Queue, Table, File Share, Data Lake storage services
- Management plane (Storage Account operations)
- BEAM integrations (Broadway, Flow, Explorer, Nx)
