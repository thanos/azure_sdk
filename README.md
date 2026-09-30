# Azure SDK

[![Hex.pm](https://img.shields.io/hexpm/v/azure_sdk.svg)](https://hex.pm/packages/azure_sdk)
[![Hex Docs](https://img.shields.io/badge/hex-docs-lightgreen.svg)](https://hexdocs.pm/azure_sdk)
[![CI](https://github.com/thanos/azure_sdk/actions/workflows/ci.yml/badge.svg)](https://github.com/thanos/azure_sdk/actions/workflows/ci.yml)
[![Coverage Status](https://coveralls.io/repos/github/thanos/azure_sdk/badge.svg?branch=main)](https://coveralls.io/github/thanos/azure_sdk?branch=main)
[![License](https://img.shields.io/hexpm/l/azure_sdk.svg)](https://github.com/thanos/azure_sdk/blob/main/LICENSE)

Azure platform SDK for Elixir and Erlang.

AzureSDK is not a Blob Storage library. It is a long-term, multi-service Azure SDK built on BEAM-native patterns: explicit client structs, OTP-ready design, first-class telemetry, and a reusable Req pipeline.

**v0.3.0** adds production Blob capabilities: bounded-memory block upload/download streams, conditional headers and blob leases, lazy listing, and SAS generation. Queue, Table, Management, and BEAM integrations follow later (see Roadmap).

See [CHANGELOG](CHANGELOG.md) for migration notes. Identity guide: [`guides/azure_identity.md`](guides/azure_identity.md).

## Installation

```elixir
def deps do
  [
    {:azure_sdk, "~> 0.3.0"}
  ]
end
```

## Quick start

```elixir
credential =
  AzureSDK.Identity.SharedKeyCredential.new(
    "myaccount",
    System.fetch_env!("AZURE_STORAGE_KEY")
  )

client =
  AzureSDK.Storage.Client.new(
    account: "myaccount",
    credential: credential
  )

{:ok, _} = AzureSDK.Storage.Container.create(client, "uploads")
{:ok, blob} = AzureSDK.Storage.Blob.upload(client, "uploads", "hello.txt", "Hello, Azure!")
```

### Stream upload / download

```elixir
{:ok, _} =
  AzureSDK.Storage.Blob.upload_stream(client, "uploads", "large.bin", file_stream,
    block_size: 4 * 1024 * 1024
  )

{:ok, chunks} = AzureSDK.Storage.Blob.download_stream(client, "uploads", "large.bin")
```

### Local development with Azurite

```bash
docker compose up -d
```

```elixir
client =
  AzureSDK.Storage.Client.new(
    account: "devstoreaccount1",
    credential:
      AzureSDK.Identity.SharedKeyCredential.new(
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
AzureSDK
├── Identity Plane      (SharedKey, SAS, Entra TokenCredentials)
├── Data Plane          (Blob; Queue/Table reserved for later releases)
├── Management Plane    (reserved for v0.6)
└── Platform Services   (Pipeline, Telemetry, Retry, TokenCache)
```

See `plans/architecture.md` for the full design.

## Roadmap

v0.1.0 established the platform foundation. Releases after v0.2.0 deepen Blob before expanding into more services.

| Version | Theme | Key Deliverables |
|---------|-------|------------------|
| **v0.1.0** | Foundation | Blob, Container, pipeline, SharedKey/SAS, telemetry, Azurite |
| **v0.2.0** | Identity + Core Contracts | TokenCredential, Entra credentials, TokenCache, Bearer, retry hardening, ServiceVersion |
| **v0.3.0** | Production Blob | Real streaming, block blobs, conditions, lazy pagination, SAS generation |
| **v0.4.0** | Queue Storage | Queue CRUD, messages, safe retry semantics |
| **v0.5.0** | Table Storage | Entities, OData queries, batch, Table signing |
| **v0.6.0** | Management Plane | ARM client, LRO, StorageAccount |
| **v0.7.0** | BEAM Integrations | Broadway, Flow (use-case driven) |

### v0.3.0 - Production Blob Storage (Current)

- Bounded-memory `upload_stream` via Put Block / Put Block List
- Range-based `download_stream`
- ETag conditions, blob leases, richer listing (`list_page` / lazy stream)
- SAS generation (Shared Key service SAS and user-delegation helpers)

### v0.4.0 - Queue Storage

Queue CRUD and messages with idempotent-safe retry defaults from v0.2.0.

### Later

Table needs a distinct Shared Key format; ARM benefits from mature OAuth/paging/retry. Design notes live under [`plans/`](https://github.com/thanos/azure_sdk/tree/main/plans).

### Versioning

SemVer pre-1.0.0: minor versions may include breaking changes with CHANGELOG notice.

## Documentation

| Resource | Location |
|----------|----------|
| API reference and guides | [hexdocs.pm/azure_sdk](https://hexdocs.pm/azure_sdk) |
| Architecture plans | [`plans/`](https://github.com/thanos/azure_sdk/tree/main/plans) |
| Livebooks | [`livebooks/`](https://github.com/thanos/azure_sdk/tree/main/livebooks) |
| Changelog | [`CHANGELOG.md`](https://github.com/thanos/azure_sdk/blob/main/CHANGELOG.md) |
| Security / dependency advisories | [`SECURITY.md`](https://github.com/thanos/azure_sdk/blob/main/SECURITY.md) |

## Telemetry

Every operation emits `:telemetry` events:

```elixir
:telemetry.attach("ex-azure", [:azure_sdk, :request, :stop], fn _, %{duration: d}, meta, _ ->
  IO.inspect({d, meta})
end, nil)
```

See `plans/telemetry-design.md` for the full event catalog.

## License

MIT
