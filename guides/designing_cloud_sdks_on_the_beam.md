# Designing Cloud SDKs on the BEAM

Architectural patterns from ExAzure that apply to any HTTP-based cloud SDK.

## BEAM Advantages

Official SDKs can't assume: lightweight processes, `:telemetry`, supervision trees, Broadway/Flow/Explorer, Livebook, hot upgrades.

A BEAM-native SDK leverages these by design.

## Layered Architecture

```
Service Modules (Blob, S3)     — Public API
Service Clients                — Configuration
Core Pipeline                  — Cross-cutting concerns
Identity / Credentials         — Authentication
Transport (Req → Finch → Mint) — HTTP
```

Service modules never import HTTP libraries.

## Design Principles

**1. Clients are data, not processes** — passable structs, not hidden Agents.

**2. Credentials are values** — construct at app boundary, pass to clients.

**3. Pipelines compose middleware** — auth, retry, telemetry as modules.

**4. Errors are structs** — `{:error, %Error{status:, code:, ...}}`.

**5. Internal formats stay internal** — parse XML/JSON, return maps.

**6. Telemetry at two levels** — operations (business) and requests (infra).

## OTP Patterns

**TokenCache (v0.2.0)** — supervised process, single refresh point.

**Broadway (v0.6.0)** — blob producer with backpressure.

**Flow (v0.6.0)** — parallel uploads with `Flow.map`.

## Testing

| Layer | Type | Tool |
|-------|------|------|
| Signing | Property | StreamData |
| Parsing | Unit | Fixtures |
| Retry | Unit | Mock responses |
| E2E | Integration | Local emulator |

Azurite (Azure), LocalStack (AWS), fake-gcs-server (GCP).

## Namespace Reservation

Ship stubs on day one:

```elixir
defmodule ExAzure.Storage.Queue do
  @moduledoc "Planned v0.3.0."
end
```

## Documentation as Code

- `plans/` — why
- `guides/` — how to think
- `livebooks/` — how to do (CI-validated)

## v0.1.0 Lessons

1. Research before code prevented dead ends
2. Pipeline first made Blob easy
3. Azurite reveals signing edge cases (double account name)
4. Disable Req retry to avoid double layers
5. `:telemetry.execute` is cheap, invaluable

## Cross-Cloud Pattern

| Concept | Azure | AWS (hypothetical) |
|---------|-------|---------------------|
| Credential | SharedKey | AccessKey |
| Signing | HMAC-SHA256 | SigV4 |
| Pipeline | Core.Pipeline | Same pattern |
| Emulator | Azurite | LocalStack |
| Events | `[:ex_azure, ...]` | `[:ex_aws, ...]` |

Architecture transfers; signing and parsers change per cloud.

## Further Reading

- `plans/architecture.md`
- `guides/building_sdk_pipelines_with_req.md`
- `guides/telemetry_driven_sdk_design.md`
