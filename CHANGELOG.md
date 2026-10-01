# Changelog

## v0.4.0 - 2026-10-01

### Added

- `AzureSDK.Storage.Queue`: create, delete, exists?, metadata, set_metadata,
  properties (approximate message count), list / list_page / list_stream
  (with `:include_metadata`), clear_messages
- `AzureSDK.Storage.Queue.Message`: put, get, peek, delete, update.
  - `:message_encoding` is `:base64` (default; Azure Functions and v11 SDKs)
    or `:none` (plain text; v12 Python and .NET defaults). Text that is not
    valid Base64 is reported as `InvalidMessageEncoding`, never guessed.
  - `update/4` without `:content` changes only the visibility timeout and keeps
    the message body.
  - `put/4` returns `{:ok, message}` (id, pop receipt, times; no content).
  - `delete/4` treats `404 MessageNotFound` as already deleted.
  - Out-of-range counts, timeouts, TTLs and bodies over 64 KiB return
    `InvalidArgument` without a request.
- Put Message, Get Messages and Update Message set `metadata.idempotent: false`
  so ambiguous 5xx / transport failures are not retried (Put would duplicate,
  Get has visibility side effects, Update issues a new pop receipt)
- `Queue.StreamError`
- Livebook `livebooks/queue_storage.livemd`

## v0.3.0 - 2026-09-30

### Breaking

- `Blob.download_stream/4` returns `{:ok, stream}` after one HEAD request and
  fetches the blob with Range requests while you enumerate. A failed range
  raises `AzureSDK.Storage.Blob.StreamError` during enumeration; v0.2.0
  downloaded everything first and returned `{:error, error}` up front.
- `download_stream/4` pins the blob's ETag: if the blob is overwritten while you
  enumerate, the next range raises `StreamError` (HTTP 412) instead of returning
  bytes from the new version.
- `Blob.upload_stream/5` always returns `content: nil`; v0.2.0 returned the
  uploaded bytes.
- The `[:azure_sdk, :blob, :put]` event from `upload_stream/5` carries
  `streaming: true` instead of `buffered: true`.
- `Container.list_stream/2` and `list_blobs_stream/3` raise
  `AzureSDK.Storage.Container.StreamError` when a page fails.

### Changed

- `Blob.upload_stream/5` uses Put Block / Put Block List with bounded `:block_size`
  (default 4 MiB) instead of buffering the full enumerable. Each upload uses a
  random block-ID prefix, so concurrent uploads to one blob cannot mix blocks.
  An upload that would need more than 50,000 blocks returns `BlockCountExceeded`.
- `Blob.download_stream/4` uses HTTP Range requests with `:chunk_size` instead of
  a single full download

### Added

- `AzureSDK.Storage.Conditions`: `If-*` and `:lease_id` headers for blob ops;
  date conditions accept a `DateTime`
- `AzureSDK.Storage.Blob.Block`: `put_block/6`, `put_block_list/5`,
  `upload_prefix/0`, `block_id/3`
- `AzureSDK.Storage.Blob.Lease`: acquire, renew, change, release, break.
  `acquire/4` always sends a proposed lease id so a retried acquire is safe.
- `Blob.download/4` `:range` option for a single byte range
- `Container.list_page/2`, `list_stream/2`, `list_blobs_page/3`, `list_blobs_stream/3`
  with `:prefix`, `:max_results`, `:marker`
- `AzureSDK.Storage.Sas`: Shared Key blob/container SAS generation and
  user-delegation key / SAS helpers. Permissions are normalized to service
  order, times are signed as UTC, and missing options return `InvalidArgument`.
- `Blob.StreamError` and `Container.StreamError` exceptions

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
