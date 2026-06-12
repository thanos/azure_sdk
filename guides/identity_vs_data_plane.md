# Identity vs Data Plane

Two distinct Azure API layers. Confusing them causes wrong endpoints and auth failures.

## The Two Planes

**Data plane** — read/write storage content:

```
PUT https://myaccount.blob.core.windows.net/photos/vacation.jpg
Authorization: SharedKey myaccount:abc123...
```

**Management plane** — provision/configure resources via ARM:

```
PUT https://management.azure.com/subscriptions/{sub}/.../storageAccounts/foo
Authorization: Bearer eyJ0eXAi...
```

| | Data | Management |
|-|------|------------|
| Endpoint | `{account}.blob.core.windows.net` | `management.azure.com` |
| Auth | Shared Key, SAS, AAD | OAuth2 Bearer only |
| Body | XML/binary | JSON |
| Speed | Fast, high-volume | May be async (LRO) |

## Common Mistakes

| Mistake | Result |
|---------|--------|
| Shared Key against ARM | 401 |
| Bearer without storage scope | 403 |
| ARM API to upload file | Wrong API |

## AzureSDK Modules

```
Data: Blob, Container (v0.1.0), Queue/Table (future)
Mgmt: Management.* (v0.5.0 stubs)
```

## Credentials

**Data (v0.1.0):** `SharedKeyCredential`, `SASCredential`

**Management (v0.2.0+):** `ClientSecretCredential`, `ManagedIdentityCredential`

Scope: `https://management.azure.com/.default`

## Same Pipeline

Both use `Core.Pipeline.run/3`. Credential type determines signing — service modules don't branch on plane.

## Typical App Flow

1. Management: create storage account (v0.5.0)
2. Management: configure firewall (v0.5.0)
3. Data: upload logs (v0.1.0 ✓)
4. Data: download uploads (v0.1.0 ✓)

Steps 1–2 via Portal/CLI/Terraform today.

## Endpoints

```elixir
# Data
"https://#{account}.blob.core.windows.net"
"http://127.0.0.1:10000/#{account}"  # Azurite

# Management (future)
"https://management.azure.com/subscriptions/#{sub_id}/..."
```

## Further Reading

- [`plans/data-plane-vs-management-plane.md`](https://github.com/thanos/azure_sdk/blob/main/plans/data-plane-vs-management-plane.md)
- [`plans/identity-architecture.md`](https://github.com/thanos/azure_sdk/blob/main/plans/identity-architecture.md)
- `guides/management_plane_design.md`
