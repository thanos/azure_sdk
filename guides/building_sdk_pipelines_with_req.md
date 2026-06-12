# Building SDK Pipelines with Req

Why AzureSDK uses Req and how to build SDK pipelines on the BEAM.

## The Problem

Cloud APIs share auth, retry, telemetry, errors, and pooling. Without a pipeline, every function reimplements these.

## AzureSDK Pattern

```elixir
def upload(client, container, name, content) do
  request = Request.new(method: :put, path: ..., body: content, ...)
  Pipeline.run(Client.to_core_client(client), request)
end
```

Service modules describe *what*; pipeline handles *how*.

## Why Req?

Modern Elixir HTTP: composable, Finch pooling, Mint protocol, active maintenance. De facto for new projects.

```elixir
Req.request(method: :get, url: url, retry: false)
```

AzureSDK disables Req retry — Azure-specific codes and `[:azure_sdk, :retry]` telemetry need custom logic.

## Pipeline Step Example

```elixir
def apply(%Request{} = request, %SharedKeyCredential{} = cred) do
  request |> ensure_ms_headers() |> sign_and_authorize(cred)
end
```

Pure functions on structs — unit testable without network.

## Chain Orchestration

Imperative (not Req plugs) because retry must re-sign and telemetry spans retries:

```
request |> sign() |> Telemetry.apply() |> transport() |> maybe_retry() |> handle_response()
```

## Per-Client Config

```elixir
client = Storage.Client.new(account: "a", credential: c, req_options: [receive_timeout: 60_000])
Pipeline.run(client, request, receive_timeout: 120_000)  # per-call override
```

## Error Boundaries

```elixir
{:error, %Error{cause: %Mint.TransportError{}}}     # transport
{:error, %Error{status: 404, code: "BlobNotFound"}} # HTTP
{:ok, %Response{status: 200, body: ...}}            # success
```

## Testing

```elixir
test "canonicalizes x-ms headers" do
  string = SharedKey.string_to_sign(request, "account")
  assert string =~ "x-ms-date:"
end
```

Integration tests hit Azurite.

## Build Your Own SDK

1. Request struct (method, path, headers, body, metadata)
2. Client struct (credential, endpoint, transport opts)
3. Signing middleware per auth scheme
4. Req transport with `retry: false`
5. `:telemetry` at operation and request level
6. `{:ok,_}` / `{:error, %YourError{}}`

## Anti-Patterns

- Req directly from service modules
- Global credential config
- Double retry layers
- Leaking XML/JSON to consumers

## Further Reading

- [`plans/pipeline-design.md`](https://github.com/thanos/azure_sdk/blob/main/plans/pipeline-design.md)
- [`plans/req-integration.md`](https://github.com/thanos/azure_sdk/blob/main/plans/req-integration.md)
- `guides/designing_cloud_sdks_on_the_beam.md`
