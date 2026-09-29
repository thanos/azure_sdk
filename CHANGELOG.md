# Changelog

## v0.2.0 — 2026-09-29

### Breaking

- `AzureSDK.Identity.Credential` now requires `authorize_request/2` returning
  `{:ok, request} | {:error, error}` (replaces infallible `sign_request/2`)
- Entra credentials implement `TokenCredential.get_token/3` instead of signing directly
- Retry policy defaults include `jitter: true`; transport errors retry only for idempotent requests
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

## v0.1.0 — 2026-06-12

### Added

- Multi-service architecture with Identity, Data Plane, Management, and Platform layers
- `AzureSDK.Core.Pipeline` — reusable Req-based request pipeline with retry and telemetry
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
