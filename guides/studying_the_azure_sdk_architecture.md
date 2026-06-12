# Studying the Azure SDK Architecture

Microsoft's Azure SDKs share a common architecture. Understanding it helps you contribute to ExAzure.

## Hierarchy

```
Service Client → Pipeline/Policies → HTTP
```

ExAzure mapping:

```
Storage.Blob.upload/4 → Core.Pipeline.run/3 → Req.request/1
```

## Study Checklist

### 1. Design Guidelines

[azure.github.io/azure-sdk](https://azure.github.io/azure-sdk/) — naming, errors, versioning.

### 2. REST API Spec

Source of truth: methods, headers (`x-ms-version`, `x-ms-date`), auth scheme, body format.

### 3. Python SDK Source

Most readable reference. Study `azure-storage-blob` for client construction, signing, pagination.

### 4. Map Policies to ExAzure

| Azure Core | ExAzure |
|------------|---------|
| `BearerTokenCredentialPolicy` | Future `Pipeline.Bearer` |
| `RetryPolicy` | `Core.Retry` |
| `LoggingPolicy` | Telemetry + future logging |

### 5. Document Before Implementing

Capture auth, parsing, pagination, errors, telemetry in `plans/` before code.

## Key Patterns

**Client options bag** — `req_options`, `retry`, `api_version` on client struct.

**Credential protocol** — `Credential` behaviour with `sign_request/2`.

**LRO polling** — ARM async ops via `Azure-AsyncOperation` header (v0.5.0).

**Pagination** — continuation tokens; v0.1.0 returns first page.

## Adopt vs Adapt

**Adopt:** client-centric API, credential abstraction, pipeline, structured errors, API versions.

**Adapt for BEAM:** `:telemetry`, `{:ok,_}` tuples, OTP token cache, Broadway/Flow hooks.

**Skip:** auto-generated complexity, heavy inheritance.

## Exercise: Trace a Blob Upload

**Python:** `BlobClient.upload_blob()` → pipeline → `SharedKeyCredentialPolicy` → transport

**ExAzure:** `Blob.upload/4` → `Pipeline.run` → `SharedKey.apply` → `Req.request`

Compare with `SharedKey.string_to_sign/2`.

## Further Reading

- [`plans/azure-sdk-study.md`](https://github.com/thanos/ex_azure/blob/main/plans/azure-sdk-study.md)
- [`plans/pipeline-design.md`](https://github.com/thanos/ex_azure/blob/main/plans/pipeline-design.md)
- [Azure SDK GitHub](https://github.com/Azure/azure-sdk-for-python)
