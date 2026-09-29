# Identity Plane Architecture

Authentication is a first-class subsystem. Storage modules never compute signatures - credentials plug into `AzureSDK.Core.Pipeline`.

## Principles

1. Credentials authorize requests; services do not.
2. Two behaviours: request credentials (`Credential`) and token credentials (`TokenCredential`).
3. Explicit credentials - no global config for keys or secrets.
4. Token acquisition is fallible: `{:ok, token} | {:error, Error.t()}`.

## Behaviours (v0.2.0)

### `AzureSDK.Identity.Credential`

```elixir
@callback authorize_request(credential, Request.t()) ::
            {:ok, Request.t()} | {:error, Error.t()}
```

Used by Shared Key and SAS.

### `AzureSDK.Identity.TokenCredential`

```elixir
@callback get_token(credential, scopes, opts) ::
            {:ok, AccessToken.t()} | {:error, Error.t()}

@callback cache_key(credential) :: term()
```

Used by Entra/OAuth credentials. The pipeline acquires a token via `TokenCache`, then applies `Pipeline.Bearer`.

## Pipeline Dispatch

| Credential | Authorization |
|------------|---------------|
| `SharedKeyCredential` | `SharedKey account:sig` header |
| `SASCredential` | SAS query params |
| Any `TokenCredential` | `Bearer {token}` via `TokenCache` + `Pipeline.Bearer` |

Auth failures return `{:error, %AzureSDK.Error{}}` and are **not** HTTP-retried.

On HTTP 401 with a token credential, the pipeline invalidates the cache entry and re-authorizes once.

## Implemented Credentials

### SharedKeyCredential / SASCredential

Unchanged crypto from v0.1.0; `authorize_request/2` returns `{:ok, request}`.

### ClientSecretCredential

POST `{authority}/{tenant}/oauth2/v2.0/token` with client credentials.
Default storage scope: `https://storage.azure.com/.default`.

### ManagedIdentityCredential

IMDS GET `http://169.254.169.254/metadata/identity/oauth2/token` with `Metadata: true`.
Optional `:client_id` for user-assigned identity. `:endpoint` overridable for tests.

### WorkloadIdentityCredential

Reads `AZURE_FEDERATED_TOKEN_FILE`, exchanges as client assertion (JWT bearer).

### EnvironmentCredential

Builds ClientSecret or WorkloadIdentity from:

- `AZURE_TENANT_ID`, `AZURE_CLIENT_ID`, `AZURE_CLIENT_SECRET`
- or `AZURE_FEDERATED_TOKEN_FILE`
- optional `AZURE_AUTHORITY_HOST`

### DefaultAzureCredential

Chain: Environment → WorkloadIdentity (if env present) → ManagedIdentity.
Short-circuits on first success.

## TokenCache

Supervised GenServer (`AzureSDK.Application`):

- Key: `{cache_key(credential), sorted_scopes}`
- Stale when `expires_at` is within 5 minutes
- Coalesces concurrent acquires for the same key
- Telemetry: `[:azure_sdk, :auth, :token_cache, :hit | :miss]`, `[:azure_sdk, :auth, :token, :acquire]`

## Security

- Never log keys, SAS sigs, or tokens.
- Telemetry includes `scheme` / cache key type only.
- Token refresh synchronized in cache to prevent thundering herd.

## Related Documents

- `README.md` (Roadmap) - v0.2.0 Identity + Core Contracts
- `pipeline-design.md`
- `guides/azure_identity.md`
