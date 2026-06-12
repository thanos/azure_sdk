# Changelog

## v0.1.0 — 2026-06-12

### Added

- Multi-service architecture with Identity, Data Plane, Management, and Platform layers
- `ExAzure.Core.Pipeline` — reusable Req-based request pipeline with retry and telemetry
- Identity plane: `SharedKeyCredential`, `SASCredential`, credential behaviour
- Blob Storage: upload, download, delete, metadata, listing, streaming helpers
- Container management: create, delete, list, list blobs, metadata
- Standardized `ExAzure.Error` struct
- XML parsers hidden behind public structs and maps
- Azurite integration tests and Docker Compose environment
- Architecture plans, educational guides, and Livebooks
- GitHub Actions CI: format, Credo, Doctor, Sobelow, Dialyzer, test matrix, docs

### Design stubs (documented, not implemented)

- OAuth credentials (Client Secret, Managed Identity, DefaultAzureCredential)
- Queue, Table, File Share, Data Lake storage services
- Management plane (Storage Account operations)
- BEAM integrations (Broadway, Flow, Explorer, Nx)
