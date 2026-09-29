# Release Plan — v0.1.0

Deliverables and release process for the AzureSDK v0.1.0 Foundation Release.

## v0.1.0 Scope

### Core Platform ✓

`Core.Client`, `Request`, `Response`, `Pipeline`, `Retry`, `Telemetry`, `Error`, `Xml.*` parsers.

### Identity Plane ✓

`Credential` behaviour, `SharedKeyCredential`, `SASCredential`, `Pipeline.SharedKey`, `Pipeline.SAS`. Stubs: `ClientSecretCredential`, `ManagedIdentityCredential`, `TokenCache`.

### Data Plane ✓

`Storage.Client`, `Storage.Blob`, `Storage.Container`. Stubs: Queue, Table, FileShare, DataLake.

### Management / Integrations ✓

`Management.Client` stub; Integrations stubs (Livebook, Explorer, Broadway, Flow, Nx).

### Testing ✓

Unit (signing, XML, retry), property (StreamData canonicalization), integration (Azurite via `AzuriteCase`), Docker Compose for CI.

### Documentation

- [x] `plans/` architecture documents
- [x] `guides/` educational content
- [x] `RELEASE_NOTES.md`, `CHANGELOG.md`
- [ ] `livebooks/` executable notebooks
- [ ] README with project description

### CI/CD (Planned)

GitHub Actions: format, credo, doctor, dialyzer, sobelow, OTP/Elixir matrix, Azurite integration, docs build, Livebook validation.

## Quality Gates

| Gate | Target |
|------|--------|
| Test coverage | 80%+ |
| Signing coverage | 95%+ |
| Credo / Dialyzer / Sobelow | zero issues |

## Release Process

```bash
mix format --check-formatted && mix credo --strict
mix doctor --full && mix dialyzer && mix sobelow --config
AZURITE=true mix test && mix coveralls.html
git tag v0.1.0 && git push origin v0.1.0
mix hex.publish
```

Update version in `mix.exs`, `CHANGELOG.md`, `RELEASE_NOTES.md`.

## Dependencies (v0.1.0)

```elixir
{:req, "~> 0.5"}, {:sweet_xml, "~> 0.7"}, {:telemetry, "~> 1.3"}
```

Elixir `~> 1.16`.

## Hotfix Process

Branch from tag, fix, release patch, cherry-pick to main.

## Future Cadence

v0.2.0 Identity (highest priority) → v0.3.0 Queue → v0.4.0 Table → v0.5.0 Management → v0.6.0 Integrations.

## Related Documents

- `README.md` (Roadmap) — feature detail per version
- `livebook-strategy.md` — notebook validation
