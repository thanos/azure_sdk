# Migrating from Azurex

[Azurex](https://github.com/jakobht/azurex) served Elixir Blob Storage needs. ExAzure is the successor platform SDK.

## Why Migrate?

- Platform scope (Queue, Table, Management coming)
- Built-in `:telemetry`
- `%ExAzure.Error{}` everywhere
- Req/Finch instead of HTTPoison
- Azurite-first CI
- Explicit credentials; OAuth in v0.2.0

See [`plans/azurex-review.md`](https://github.com/thanos/ex_azure/blob/main/plans/azurex-review.md) for details.

## Dependency

```elixir
# Remove: {:azurex, "~> 1.1"}
# Add:
{:ex_azure, "~> 0.1.0"}
```

## Client Setup

**Azurex:** config-based or inline keys at call site.

**ExAzure:**

```elixir
credential = SharedKeyCredential.new(account, key)
client = Storage.Client.new(account: account, credential: credential)
Blob.upload(client, container, blob, content)
```

Create client once at startup; pass to all operations.

## Operation Mapping

| Azurex | ExAzure |
|--------|---------|
| `put_blob/4` | `Blob.upload/4` |
| `get_blob/3` | `Blob.download/3` |
| `delete_blob/3` | `Blob.delete/3` |
| `list_blobs/2` | `Container.list_blobs/2` |
| `create_container/2` | `Container.create/2` |
| `delete_container/2` | `Container.delete/2` |
| `list_containers/1` | `Container.list/1` |

Returns structured maps, not raw HTTP:

```elixir
{:ok, blob} = Blob.download(client, "c", "f.txt")
blob.content
blob.properties.etag
```

## Errors

```elixir
case Blob.download(client, c, n) do
  {:ok, %{content: data}} -> data
  {:error, %Error{status: 404}} -> nil
  {:error, %Error{} = e} -> {:error, e}
end
```

## Config Migration

```elixir
def azure_client do
  Storage.Client.new(
    account: System.get_env("AZURE_STORAGE_ACCOUNT"),
    credential: SharedKeyCredential.new(
      System.get_env("AZURE_STORAGE_ACCOUNT"),
      System.get_env("AZURE_STORAGE_KEY")
    )
  )
end
```

## Azurite

```elixir
Storage.Client.new(
  account: "devstoreaccount1",
  credential: SharedKeyCredential.new("devstoreaccount1", "..."),
  endpoint: "http://127.0.0.1:10000/devstoreaccount1"
)
```

Double-account signing handled automatically.

## Not Yet in ExAzure

| Feature | Status |
|---------|--------|
| SAS generation | Planned |
| Page blobs | Block blobs only |
| Queue/Table | v0.3.0 / v0.4.0 |

## Incremental Strategy

1. Add `ex_azure` alongside `azurex`
2. Create client in context module
3. Migrate one operation at a time
4. Add telemetry handlers
5. Remove `azurex`

## Further Reading

- `guides/azure_for_elixir_developers.md`
- [`livebooks/getting_started.livemd`](https://github.com/thanos/ex_azure/blob/main/livebooks/getting_started.livemd)
