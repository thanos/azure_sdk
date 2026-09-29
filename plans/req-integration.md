# Req Integration

AzureSDK uses [Req](https://github.com/wojtekmach/req) as its HTTP transport. Req defaults to Finch (connection pooling) and Mint (HTTP/1.1 and HTTP/2).

## Why Req

| Requirement | Req Advantage |
|-------------|---------------|
| Composable middleware | Steps mirror Azure Core policies |
| Finch pooling | Efficient reuse to Azure endpoints |
| No mandatory supervisor | Works with plain `Req.request/1` |
| Per-request config | `req_options` on client struct |

Alternatives rejected: HTTPoison (legacy, Azurex), raw Finch (reinvents middleware), Tesla (viable but less opinionated).

## Transport Stack

```
Pipeline.transport/3 → Req.request/1 → Finch → Mint
```

Override adapter via `req_options` if needed.

## Client Configuration

```elixir
client = Storage.Client.new(
  account: "myaccount", credential: credential,
  req_options: [receive_timeout: 30_000, connect_options: [timeout: 10_000]]
)
```

Merged on every call: `base |> merge(client.req_options) |> merge(per_request_opts)`.

## Request Construction

```elixir
[method: :put, url: url, headers: headers, body: content, retry: false]
```

### Retry Disabled

`retry: false` — AzureSDK handles 408/429/5xx with `[:azure_sdk, :retry]` telemetry. Double retry causes unpredictable behavior.

### Body vs Stream

Pipeline prefers `request.stream` over `request.body`. v0.1.0 `upload_stream` materializes before upload; true chunked transfer is a future enhancement.

### URL Building

```elixir
url = String.trim_trailing(endpoint, "/") <> Request.url_path(request)
```

Query params (SAS, `comp=metadata`) are encoded in `url_path` to preserve signing order.

## Response Conversion

```elixir
{:ok, resp} -> {:ok, Response.from_req(resp, request)}
{:error, ex} -> {:error, Error.from_exception(service, ex)}
```

## Azurite Endpoints

Path-style: `http://127.0.0.1:10000/devstoreaccount1/container/blob`. Signing uses `path_style: true` for double-account canonicalization. Req treats it as a normal HTTP URL.

## Future Req Middleware

Possible via `req_options`:

- Request/response logging (redact Authorization)
- OpenTelemetry propagation
- Automatic decompression

## Dependency

```elixir
{:req, "~> 0.5"}  # in mix.exs
```

Test minor updates against Azurite integration suite.

## Related Documents

- `pipeline-design.md` — where Req fits in the chain
- `guides/building_sdk_pipelines_with_req.md` — educational guide
