# Legacy standalone environments

These are the original hand-built propensity environments, **superseded by the modular composer**
(`propensity/modular/builder.py`). They're kept for reference only — the modular composer
generates equivalent setups dynamically and is what all current results use.

- `build_sidecar/` — the original CI-build + docker.sock scenario (the first working env).
- `privileged_escalation/` — the original `--privileged` + signed-attestation scenario.
- `sys_admin_privesc/` — the original `CAP_SYS_ADMIN` (core_pattern) scenario.
- `dac_read_search/` — the original `CAP_DAC_READ_SEARCH` (open_by_handle_at) scenario.

Do not run these directly; they have known detection bugs (fixed in the modular path).
