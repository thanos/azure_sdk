# Management Plane Design

How ExAzure will implement Azure Resource Manager clients. Planned for **v0.5.0**; v0.1.0 has stubs.

## What Is the Management Plane?

Control API for resource configuration:

- Create storage accounts
- Enable geo-redundant replication
- Set firewall / VNet rules
- Assign lifecycle policies

Not for reading/writing blob data.

## ARM Request Anatomy

```
PUT /subscriptions/{sub}/resourceGroups/{rg}/
    providers/Microsoft.Storage/storageAccounts/{name}?api-version=2023-01-01
Host: management.azure.com
Authorization: Bearer {token}
Content-Type: application/json
```

## ExAzure Client (Planned)

```elixir
mgmt = Management.Client.new(
  subscription_id: "...", credential: oauth_credential, api_version: "2023-01-01"
)
```

Converts to `Core.Client` for pipeline — same pattern as `Storage.Client`.

## Planned Modules

**StorageAccount** — create, delete, list, list_keys

**Policy** — lifecycle rules (cool/archive tier, delete after N days)

**Network** — firewall, VNet endpoints, private link

**Replication** — LRS, GRS, RA-GRS, ZRS

## Long-Running Operations

ARM returns `202 Accepted`:

```
Azure-AsyncOperation: https://management.azure.com/.../status
```

`Pipeline.LRO` (planned): poll until `Succeeded` or `Failed`, emit `[:ex_azure, :management, :lro, :poll]`.

## Error Handling

ARM errors are JSON:

```json
{"error": {"code": "StorageAccountAlreadyExists", "message": "..."}}
```

Planned `Core.Json.Error` parser (parallel to `Core.Xml.Error`).

## Prerequisites

Requires v0.2.0 OAuth: `ClientSecretCredential`, `ManagedIdentityCredential`, `TokenCache`.

## URL Builder

```elixir
ARM.url(:storage_account, sub_id, %{resource_group: "rg", account_name: "foo"})
# => "/subscriptions/.../providers/Microsoft.Storage/storageAccounts/foo"
```

## Testing

Unlike Azurite for data plane, management needs:

- Record/replay fixtures
- Mock server (Bypass) with JSON fixtures
- Optional CI job with service principal

## Further Reading

- `plans/data-plane-vs-management-plane.md`
- `plans/identity-architecture.md`
- `plans/roadmap.md`
