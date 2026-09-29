# Telemetry Design

AzureSDK emits `:telemetry` events on every operation, request, signing event, and retry. BEAM operators attach handlers without modifying library code.

## Principles

1. **Two-level events** - operations (user calls) and requests (pipeline executes).
2. **Consistent metadata** - `service`, `operation`, resource identifiers.
3. **Native time duration** - convert in handlers.
4. **No secrets** - never emit keys, SAS sigs, or tokens.

## Event Catalog

### `[:azure_sdk, :request, :start | :stop | :attempt]`

| Event | When | Measurements | Metadata |
|-------|------|--------------|----------|
| `[:azure_sdk, :request, :start]` | Pipeline span starts | `%{}` | `service`, `operation`, `method`, `path` |
| `[:azure_sdk, :request, :attempt]` | Before each transport attempt | `%{count: 1}` | same |
| `[:azure_sdk, :request, :stop]` | Pipeline span finishes | `%{duration: native}` | same |

One logical request emits exactly one `:start` and one `:stop`; `:attempt` fires once per HTTP attempt (more than once when retrying). Count requests with `:stop`, count attempts with `:attempt`.

### `[:azure_sdk, :auth, :sign]`

After SharedKey or Bearer signing: `%{count: 1}`, metadata `scheme: :shared_key | :bearer`, plus service/operation fields (never token/key values).

### `[:azure_sdk, :auth, :token_cache, :hit | :miss]`

Token cache lookups: `%{count: 1}`, metadata `cache_key_type`.

### `[:azure_sdk, :auth, :token, :acquire]`

Token acquisition finished: `%{count: 1, duration: native}`, metadata `result: :ok | :error`, `cache_key_type`.

### `[:azure_sdk, :retry]`

Before backoff sleep: `%{count: 1, delay_ms: int}`, metadata includes `attempt`.

### Blob Operations (`AzureSDK.Storage.Blob`)

| Event | Function | Metadata |
|-------|----------|----------|
| `[:azure_sdk, :blob, :put]` | `upload/4`, `upload_stream/4` | `container`, `name`, optional `buffered: true` |
| `[:azure_sdk, :blob, :get]` | `download/4` | `container`, `name` |
| `[:azure_sdk, :blob, :delete]` | `delete/3` | `container`, `name` |
| `[:azure_sdk, :blob, :metadata]` | `metadata/3` | `container`, `name` |
| `[:azure_sdk, :blob, :set_metadata]` | `set_metadata/4` | `container`, `name` |

### Container Operations (`AzureSDK.Storage.Container`)

| Event | Function | Metadata |
|-------|----------|----------|
| `[:azure_sdk, :container, :create]` | `create/2` | `name` |
| `[:azure_sdk, :container, :delete]` | `delete/2` | `name` |
| `[:azure_sdk, :container, :list]` | `list/1` | `%{}` |
| `[:azure_sdk, :container, :list_blobs]` | `list_blobs/2` | `container` |
| `[:azure_sdk, :container, :exists]` | `exists?/2` | `name` |
| `[:azure_sdk, :container, :metadata]` | `metadata/2` | `name` |

All operation events measure `%{count: 1}`.

## Event Flow Example

`Blob.upload(client, "data", "file.txt", "hello")`:

```
1. [:azure_sdk, :blob, :put]           {container: "data", name: "file.txt"}
2. [:azure_sdk, :request, :start]      span begins
3. [:azure_sdk, :auth, :sign]          {scheme: :shared_key, account: "..."}
4. [:azure_sdk, :request, :attempt]    count (attempt 1)
5. [:azure_sdk, :request, :stop]       duration
```

On 503 retry, step 4 repeats with `[:azure_sdk, :retry]` before it.

## Implementation

| Module | Functions |
|--------|-----------|
| `Core.Telemetry` | `emit_attempt/1`, `emit_operation/3`, `emit_sign/1`, `span/2` |
| `Pipeline.Telemetry` | Pre-transport attempt count |

## Handler Example

```elixir
:telemetry.attach("ex-azure", [:azure_sdk, :request, :stop], fn
  _, %{duration: d}, meta, _ ->
    ms = System.convert_time_unit(d, :native, :millisecond)
    Logger.info("#{meta.service}.#{meta.operation} #{ms}ms")
end, nil)
```

## Future Events

| Event | Version |
|-------|---------|
| `[:azure_sdk, :queue, :*]` | v0.4.0 |
| `[:azure_sdk, :management, :*]` | v0.6.0 |

## Related Documents

- `guides/telemetry_driven_sdk_design.md` - philosophy
- `guides/azure_identity.md` - token cache events
- `pipeline-design.md` - where events fire
