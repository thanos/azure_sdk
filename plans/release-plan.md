# Release Plan - v0.3.0

Deliverables and release process for AzureSDK v0.3.0 Production Blob.

## Scope

### Production Blob (done)

- Bounded-memory `upload_stream` (Put Block / Put Block List, random block-ID prefix)
- Range `download_stream` with ETag pinning; optional `:range` on `download/4`
- `Storage.Conditions` and `Blob.Lease`
- Lazy listing: `list_page` / `list_stream` / `list_blobs_page` / `list_blobs_stream`
- `Storage.Sas` Shared Key + user-delegation generation

### Documentation (done)

- CHANGELOG (Breaking / Changed / Added), README roadmap, azurex review
- Livebooks on Hexdocs extras; package includes `livebooks/` and `SECURITY.md`
- `baoulo/RELEASE_NOTE-v0.3.0.md`, `baoulo/RELEASE_NOTICE-v0.3.0.md`

### Quality (done)

- Unit + doctests, Azurite streaming/lease/SAS coverage where applicable
- Credo, Doctor, Dialyzer, Sobelow
- CI matrix Elixir 1.17–1.20 / OTP 27–29; Coveralls on supported cover job

## Release process

```bash
mix format --check-formatted && mix credo --strict
mix doctor --full && mix dialyzer && mix sobelow --config
AZURITE=true PROPERTY=true mix test
mix docs --warnings-as-errors
mix hex.build

# after merge to main
git tag -a v0.3.0 -m "v0.3.0 Production Blob"
git push origin v0.3.0
mix hex.publish
```

Then create the GitHub Release from the tag (paste `baoulo/RELEASE_NOTE-v0.3.0.md`) and post the Reddit notice from `baoulo/RELEASE_NOTICE-v0.3.0.md`.

## Hotfix

Branch from `v0.3.0`, patch, release `0.3.x`, cherry-pick to main.

## Related

- `README.md#roadmap`
- `CHANGELOG.md`
- `baoulo/reviews/v0.3.0-review.md`
- `baoulo/RELEASE_NOTE-v0.3.0.md`
- `baoulo/RELEASE_NOTICE-v0.3.0.md`
