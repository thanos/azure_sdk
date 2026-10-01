# Release Plan - v0.4.0

Deliverables and release process for AzureSDK v0.4.0 Queue Storage.

## Scope

### Queue Storage (done)

- `Storage.Queue` CRUD, metadata, properties, clear, list_page / list_stream (`:include_metadata`)
- `Storage.Queue.Message` put / get / peek / delete / update with `:message_encoding` (`:base64` or `:none`)
- Put Message, Get Messages and Update Message: `metadata.idempotent: false`
- Azurite Queue port 10001 + Bypass retry proofs

### Documentation (done)

- CHANGELOG, README roadmap, azurex review, telemetry catalog
- Livebook `queue_storage.livemd` on Hexdocs extras
- Release note and announcement text (maintained outside the repository)

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

Then create the GitHub Release from the tag with the release note, and post the announcement.

## Hotfix

Branch from `v0.4.0`, patch, release `0.4.x`, cherry-pick to main.

## Related

- `README.md#roadmap`
- `CHANGELOG.md`
