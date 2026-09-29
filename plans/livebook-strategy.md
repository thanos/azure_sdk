# Livebook Strategy

AzureSDK uses [Livebook](https://livebook.dev) as a primary onboarding medium. Notebooks are executable, shareable, and run against Azurite without cloud accounts.

## Goals

1. Every notebook runs — CI validates execution.
2. Teach by doing — readers execute code immediately.
3. Complement `guides/` — notebooks show how, guides explain why.
4. Azurite-first — no cloud credentials in notebooks.

## Notebook Catalog

| Notebook | Content |
|----------|---------|
| `getting_started.livemd` | Install, Azurite, first upload |
| `blob_storage.livemd` | CRUD, containers, listing, metadata |
| `authentication.livemd` | SharedKey, SAS patterns |
| `streaming.livemd` | Upload/download streams |
| `telemetry.livemd` | Attach handlers, read events |

## Structure

Each notebook: Setup → Concept (markdown) → Execute → Inspect → optional Exercise.

## Azurite Setup Template

```elixir
case :gen_tcp.connect(~c"127.0.0.1", 10_000, [:binary, active: false], 500) do
  {:ok, s} -> :gen_tcp.close(s); IO.puts("Azurite OK")
  {:error, _} -> Kino.Markdown.new("Start: `docker compose up -d`")
end
```

## Client Template

```elixir
credential = SharedKeyCredential.new("devstoreaccount1", "...")
client = Storage.Client.new(
  account: "devstoreaccount1", credential: credential,
  endpoint: "http://127.0.0.1:10000/devstoreaccount1"
)
```

## Integration Module

`AzureSDK.Integrations.Livebook` — Azurite health check, client factory, telemetry Kino renderer, unique name generator. Expand as notebooks grow.

## CI Validation

```bash
docker compose up -d
# Export and execute each notebook against Azurite
```

Failed notebooks block releases.

## Kino Widgets

`Kino.Markdown`, `Kino.DataTable` (blob listings), `Kino.Term` (errors), `Kino.Input` (interactive names).

## Telemetry Demo

```elixir
:telemetry.attach("demo", [:azure_sdk, :blob, :put], fn _, m, meta, _ ->
  Kino.render({m, meta})
end, nil)
```

## Anti-Patterns

- No cloud credentials in notebooks
- Always show `{:ok,_}` / `{:error,_}` handling
- No secrets in Kino inputs

## Related Documents

- `guides/azure_for_elixir_developers.md`
- `release-plan.md`
