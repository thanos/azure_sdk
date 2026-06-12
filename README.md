# ExAzure

Azure platform SDK for Elixir and Erlang.

ExAzure is not a Blob Storage library. It is a long-term, multi-service Azure SDK built on BEAM-native patterns: explicit client structs, OTP-ready design, first-class telemetry, and a reusable Req pipeline.

**v0.1.0** ships Blob Storage on top of the foundation. Queue, Table, Management, and BEAM integrations are architected from day one.

## Installation

```elixir
def deps do
  [
    {:ex_azure, "~> 0.1.0"}
  ]
end
```

## Quick start

```elixir
credential =
  ExAzure.Identity.SharedKeyCredential.new(
    "myaccount",
    System.fetch_env!("AZURE_STORAGE_KEY")
  )

client =
  ExAzure.Storage.Client.new(
    account: "myaccount",
    credential: credential
  )

{:ok, _} = ExAzure.Storage.Container.create(client, "uploads")
{:ok, blob} = ExAzure.Storage.Blob.upload(client, "uploads", "hello.txt", "Hello, Azure!")
```

### Local development with Azurite

```bash
docker compose up -d
```

```elixir
client =
  ExAzure.Storage.Client.new(
    account: "devstoreaccount1",
    credential:
      ExAzure.Identity.SharedKeyCredential.new(
        "devstoreaccount1",
        "Eby8vdM02xNOcqFlqUwJPLlmEtlCDXJ1OUzFT50uSRZ6IFsuFq2UVErCz4I6tq/K1SZFPTOtr/KBHBeksoGMGw=="
      ),
    endpoint: "http://127.0.0.1:10000/devstoreaccount1"
  )
```

```bash
AZURITE=true mix test
```

## Architecture

```
ExAzure
├── Identity Plane      (SharedKey, SAS; OAuth planned v0.2)
├── Data Plane          (Blob v0.1; Queue, Table, File, Data Lake stubbed)
├── Management Plane    (stubbed for v0.5)
└── Platform Services   (Pipeline, Telemetry, Retry)
```

See `plans/architecture.md` for the full design.

## Documentation

| Resource | Location |
|----------|----------|
| Architecture plans | `plans/` |
| Educational guides | `guides/` |
| Livebooks | `livebooks/` |
| Changelog | `CHANGELOG.md` |
| Roadmap | `plans/roadmap.md` |

## Telemetry

Every operation emits `:telemetry` events:

```elixir
:telemetry.attach("ex-azure", [:ex_azure, :request, :stop], fn _, %{duration: d}, meta, _ ->
  IO.inspect({d, meta})
end, nil)
```

See `plans/telemetry-design.md` for the full event catalog.

## License

MIT
