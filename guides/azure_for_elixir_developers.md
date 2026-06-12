# Azure for Elixir Developers

Azure Storage concepts for Elixir developers new to the platform.

## Key Terms

| Azure Term | Analogy | ExAzure Module |
|------------|---------|----------------|
| Storage Account | S3 account namespace | `Storage.Client` |
| Container | S3 bucket | `Storage.Container` |
| Blob | S3 object | `Storage.Blob` |
| Access Key | Root API key | `SharedKeyCredential` |
| SAS Token | Pre-signed URL | `SASCredential` |

## Your First Upload

```elixir
credential = SharedKeyCredential.new("myaccount", System.get_env("AZURE_STORAGE_KEY"))

client = Storage.Client.new(account: "myaccount", credential: credential)

{:ok, _} = Container.create(client, "uploads")
{:ok, blob} = Blob.upload(client, "uploads", "hello.txt", "Hello, Azure!")
```

Every step returns `{:ok, result}` or `{:error, %ExAzure.Error{}}`.

## Local Development with Azurite

```bash
docker compose up -d
```

```elixir
client = Storage.Client.new(
  account: "devstoreaccount1",
  credential: SharedKeyCredential.new("devstoreaccount1",
    "Eby8vdM02xNOcqFlqUwJPLlmEtlCDXJ1OUzFT50uSRZ6IFsuFq2UVErCz4I6tq/K1SZFPTOtr/KBHBeksoGMGw=="),
  endpoint: "http://127.0.0.1:10000/devstoreaccount1"
)
```

The Azurite key is public — local use only.

## Authentication

**Shared Key (v0.1.0)** — full account access for server-side apps.

**SAS (v0.1.0)** — time-limited scoped access:

```elixir
SASCredential.new("sv=2024-11-04&ss=b&sp=r&se=...")
```

**Azure AD (v0.2.0)** — OAuth bearer tokens, no shared keys.

## Error Handling

```elixir
case Blob.download(client, "uploads", "missing.txt") do
  {:ok, blob} -> blob.content
  {:error, %Error{status: 404, code: "BlobNotFound"} = e} -> Logger.warning(e.message)
  {:error, %Error{} = e} -> {:error, e}
end
```

`%ExAzure.Error{}` has `status`, `code`, `message`, `request_id`, `service`.

## Telemetry

```elixir
:telemetry.attach("app", [:ex_azure, :blob, :put], fn _, _, %{container: c, name: n}, _ ->
  Logger.info("Uploaded #{c}/#{n}")
end, nil)
```

## What ExAzure Is

- Platform SDK for Azure on the BEAM (Blob today, more coming)
- Req transport, telemetry, retry, standardized errors
- OTP-ready client structs, no hidden state

## What It Isn't (Yet)

- Full Azure SDK — Queue, Table, Management in later releases
- SAS generator — v0.1.0 consumes SAS only
- Terraform replacement — use Management plane (v0.5.0) for provisioning

## Next Steps

- [`livebooks/getting_started.livemd`](https://github.com/thanos/ex_azure/blob/main/livebooks/getting_started.livemd)
- `guides/identity_vs_data_plane.md`
- `guides/migrating_from_azurex.md`
