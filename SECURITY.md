# Security

## Reporting a vulnerability

Please open a private security advisory on GitHub, or email the maintainer listed on Hex. Do not file public issues for undisclosed vulnerabilities.

## Dependency advisories

Run `mix hex.audit` after `mix deps.get` to list Hex packages with known advisories.

### Accepted: cowlib (test-only)

| Advisory | Severity | Package |
|----------|----------|---------|
| [EEF-CVE-2026-43966](https://osv.dev/vulnerability/EEF-CVE-2026-43966) / CVE-2026-43966 | Medium | cowlib 2.20.0 |
| [EEF-CVE-2026-43969](https://osv.dev/vulnerability/EEF-CVE-2026-43969) / CVE-2026-43969 | Low | cowlib 2.20.0 |

**Dependency chain:** `bypass` (test) → `plug_cowboy` → `cowboy` → `cowlib`.

**Why accepted:** cowlib is not a runtime dependency of this library. Production HTTP uses Req / Finch / Mint. Bypass only runs as a local mock HTTP server in tests, so Hex consumers of `azure_sdk` do not pull cowlib.

**Why not fixed yet:** Hex has no patched cowlib release (affected range includes 2.9.0 through 2.20.0). When a fixed version ships, override or update:

```elixir
{:cowlib, "~> 2.21", override: true}  # example; use the actual fixed version
```

Then `mix deps.update cowlib` and re-run `mix hex.audit`.

**Follow-up:** Watch [cowlib on Hex](https://hex.pm/packages/cowlib) / Cowboy releases; remove this note once audit is clean.
