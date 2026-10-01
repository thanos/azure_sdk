# Release Plan - v0.4.0

Deliverables and release process for AzureSDK v0.4.0 Queue Storage.

## Scope

### Queue Storage (done)

- `Storage.Queue` CRUD, metadata, clear, list_page / list_stream
- `Storage.Queue.Message` put / get / peek / delete / update (Base64 bodies)
- Put Message and Get Messages: `metadata.idempotent: false`
- Azurite Queue port 10001 + Bypass retry proofs

### Documentation (done)

- CHANGELOG, README roadmap, azurex review, telemetry catalog
- Livebook `queue_storage.livemd` on Hexdocs extras
- `baoulo/RELEASE_NOTE-v0.4.0.md`, `baoulo/RELEASE_NOTICE-v0.4.0.md`

### Quality

- Unit + doctests, Azurite when healthy, Credo, Doctor, Dialyzer, Sobelow
- CI matrix Elixir 1.17–1.20 / OTP 27–29

## Release process

```bash
mix format --check-formatted && mix credo --strict
mix doctor --full && mix dialyzer && mix sobelow --config
AZURITE=true PROPERTY=true mix test
mix docs --warnings-as-errors
mix hex.build

# after merge to main
git tag -a v0.4.0 -m "v0.4.0 Queue Storage"
git push origin v0.4.0
mix hex.publish
```

Then create the GitHub Release from the tag (paste `baoulo/RELEASE_NOTE-v0.4.0.md`) and post the Reddit notice from `baoulo/RELEASE_NOTICE-v0.4.0.md`.

## Hotfix

Branch from `v0.4.0`, patch, release `0.4.x`, cherry-pick to main.

## Related

- `README.md#roadmap`
- `CHANGELOG.md`
- `baoulo/RELEASE_NOTE-v0.4.0.md`
- `baoulo/RELEASE_NOTICE-v0.4.0.md`
