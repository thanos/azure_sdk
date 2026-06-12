# Telemetry-Driven SDK Design

AzureSDK designs telemetry alongside public APIs. This guide covers philosophy, events, and production patterns.

## Why Telemetry-First?

`:telemetry` is the BEAM observability bus. Libraries emit; applications attach handlers.

- No logging framework dependency
- Add metrics without library upgrades
- LiveDashboard, OTel bridges, tests all work

Official Azure SDKs have optional OTel; AzureSDK emits events with zero config.

## Two Event Levels

**Operations** — what the user called (once per API call):

```elixir
Telemetry.emit_operation(:blob, :put, %{container: c, name: n})
# => [:azure_sdk, :blob, :put]
```

**Requests** — what the pipeline executed (includes retries):

```elixir
Telemetry.span(metadata, fn -> execute_with_retry(...) end)
# => [:azure_sdk, :request, :start] then [:azure_sdk, :request, :stop] with %{duration: native}
```

## Event Reference

| Event | When | Metadata |
|-------|------|----------|
| `[:azure_sdk, :blob, :put]` | upload, upload_stream | `container`, `name` |
| `[:azure_sdk, :blob, :get]` | download | `container`, `name` |
| `[:azure_sdk, :blob, :delete]` | delete | `container`, `name` |
| `[:azure_sdk, :blob, :metadata]` | metadata | `container`, `name` |
| `[:azure_sdk, :blob, :set_metadata]` | set_metadata | `container`, `name` |
| `[:azure_sdk, :container, :*]` | create/delete/list/... | `name` or `container` |
| `[:azure_sdk, :request, :start]` | pipeline span begins | `service`, `operation`, `method`, `path` |
| `[:azure_sdk, :request, :stop]` | pipeline span ends (`%{duration: native}`) | same |
| `[:azure_sdk, :request, :attempt]` | before each HTTP attempt | same |
| `[:azure_sdk, :auth, :sign]` | SharedKey signing | `scheme`, `account` |
| `[:azure_sdk, :retry]` | backoff | `attempt`, `delay_ms` |

## Handler Examples

```elixir
# Dev logging
:telemetry.attach("dev", [:azure_sdk, :request, :stop], fn _, %{duration: d}, m, _ ->
  ms = System.convert_time_unit(d, :native, :millisecond)
  IO.puts("#{m.service}.#{m.operation} #{ms}ms")
end, nil)

# Test assertion
:telemetry_test.attach_event_handlers(self(), [[:azure_sdk, :blob, :put]])
```

## Rules for New Events

1. Name mirrors module: `[:azure_sdk, :queue, :send]`
2. Measurements numeric: `count`, `duration`, `delay_ms`
3. Metadata contextual, never secrets
4. Emit operation event before pipeline call
5. Document in `plans/telemetry-design.md`

## Security

Never in metadata: keys, SAS sigs, tokens, Authorization values, request bodies.

## Duration

Native time units — convert in handlers:

```elixir
System.convert_time_unit(d, :native, :millisecond)
```

## Further Reading

- [`plans/telemetry-design.md`](https://github.com/thanos/azure_sdk/blob/main/plans/telemetry-design.md)
- [`livebooks/telemetry.livemd`](https://github.com/thanos/azure_sdk/blob/main/livebooks/telemetry.livemd)
- [Telemetry hexdocs](https://hexdocs.pm/telemetry/)
