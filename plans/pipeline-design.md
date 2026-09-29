# Pipeline Design

`AzureSDK.Core.Pipeline` is the central execution engine for all HTTP operations. It composes signing, telemetry, retry, and transport into a reusable, testable chain.

## Flow

```
Credential → Signing → Telemetry → Transport → Response Handling
                ↑                        |
                └──── Retry loop ────────┘
```

## Entry Point

```elixir
Pipeline.run(%Client{}, %Request{}, opts \\ [])
  :: {:ok, %Response{}} | {:error, %Error{}}
```

Metadata for telemetry: `service`, `operation`, `method`, `path`.

## Execution Stages

### 1. Telemetry Span

`Telemetry.span/2` wraps the entire operation. Emits `[:azure_sdk, :request, :start]` on entry and on completion:

```
[:azure_sdk, :request, :stop]  %{duration: native_time}
```

### 2. Signing

`sign/2` dispatches through the `Credential.sign_request/2` behaviour callback:

| Credential | Implementation | Result |
|------------|----------------|--------|
| `SharedKeyCredential` | `Pipeline.SharedKey` | `Authorization: SharedKey account:sig` |
| `SASCredential` | `Pipeline.SAS` | SAS query params merged |
| OAuth credentials (future) | per-credential module | Bearer token header |

**SharedKey** ensures `x-ms-date` and `x-ms-version`, removes empty headers, computes HMAC-SHA256, emits `[:azure_sdk, :auth, :sign]`.

**SAS** merges credential params into query string, deduplicating by key.

### 3. Request Telemetry

`Pipeline.Telemetry.apply/2` emits `[:azure_sdk, :request, :attempt]` with `%{count: 1}` before each transport attempt.

### 4. Transport

Builds Req options from the request struct:

```elixir
[method: request.method, url: endpoint <> url_path,
 headers: Map.to_list(request.headers), body: body | stream,
 retry: false, decode_body: false, compressed: false]
|> Keyword.merge(client.req_options) |> Keyword.merge(opts)
```

Calls `Req.request/1`, converts via `Response.from_req/2`. Exceptions become `%AzureSDK.Error{}`.

### 5. Retry

On 408, 429, 5xx or transport errors: exponential backoff (200ms base, 2x, 5s cap), emit `[:azure_sdk, :retry]`, re-execute from signing with fresh `x-ms-date`. Default max 3 attempts.

### 6. Response Handling

Status 200–299 → `{:ok, response}`. Otherwise `{:error, Error.from_response/4}` parsing XML error bodies.

## Request Struct

Service modules build `AzureSDK.Core.Request` — the pipeline never imports `Storage.Blob`:

```elixir
%Request{method: :put, path: "/c/b", query: [], headers: %{},
         body: "...", service: :blob, operation: :put,
         metadata: %{api_version: "2024-11-04", path_style: false}}
```

## Middleware Modules

| Module | Role |
|--------|------|
| `Pipeline.SharedKey` | Storage HMAC signing |
| `Pipeline.SAS` | SAS query injection |
| `Pipeline.Telemetry` | Pre-transport count event |
| `Core.Retry` | Backoff policy |

Future: `Pipeline.Bearer` (OAuth), `Pipeline.LRO` (ARM polling).

## Design Constraints

1. Pipeline must not depend on service modules.
2. Req retry is disabled — AzureSDK owns retry logic.
3. Re-sign on every retry attempt (fresh timestamp).
4. Per-request `opts` pass through to Req for timeouts.

## Testing

- Unit test `SharedKey.string_to_sign/2` without network
- Property test canonicalization with StreamData
- Integration test full pipeline against Azurite

## Related Documents

- `req-integration.md` — Req/Finch/Mint transport
- `telemetry-design.md` — all emitted events
- `identity-architecture.md` — credential signing
