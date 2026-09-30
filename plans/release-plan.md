# Release Plan - v0.2.0

Deliverables and release process for AzureSDK v0.2.0 Identity + Core Contracts.

## Scope

### Identity (done)

- Fallible `Credential.authorize_request/2`
- `TokenCredential`, `AccessToken`, `Pipeline.Bearer`
- Client Secret, Managed Identity, Workload Identity, Environment, DefaultAzureCredential
- Supervised `TokenCache` (coalesce, expiry buffer, failure isolation)
- Secret redaction via `Inspect`

### Core (done)

- Retry: jitter, Retry-After / x-ms-retry-after-ms, idempotent transport, 401 refresh-once
- `AzureSDK.Application` starts TokenCache
- `Storage.ServiceVersion`

### Documentation (done)

- CHANGELOG, README roadmap, `guides/azure_identity.md`
- Livebooks (authentication, blob, streaming, telemetry, getting started)
- Hex package includes `guides/` for docs extras

### Quality (done)

- Unit + doctests, Azurite integration, Credo, Doctor, Dialyzer, Sobelow
- CI matrix Elixir 1.17–1.20 / OTP 27–29; Coveralls on 1.20/OTP 28

## Release process

```bash
mix format --check-formatted && mix credo --strict
mix doctor --full && mix dialyzer && mix sobelow --config
AZURITE=true PROPERTY=true mix test
mix docs --warnings-as-errors
mix hex.build

# after merge to main
git tag -a v0.2.0 -m "v0.2.0 Identity + Core Contracts"
git push origin v0.2.0
mix hex.publish
```

Then create the GitHub Release from the tag (paste `baoulo/RELEASE_NOTE-v0.2.0.md`) and post the Reddit notice from `baoulo/RELEASE_NOTICE-v0.2.0.md`.

## Hotfix

Branch from `v0.2.0`, patch, release `0.2.x`, cherry-pick to main.

## Related

- `README.md#roadmap`
- `CHANGELOG.md`
- `baoulo/RELEASE_NOTE-v0.2.0.md`
- `baoulo/RELEASE_NOTICE-v0.2.0.md`
