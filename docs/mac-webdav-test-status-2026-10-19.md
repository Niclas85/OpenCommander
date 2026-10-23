# WebDAV live test: explicitly deferred

User permitted skipping the test if setup/simulation is not suitable.

Read-only checks against authorized NAS 192.168.0.22:
- SMB Test share is mounted at /Volumes/Test.
- TCP 5005/5006 unavailable; no service detected at these usual WebDAV ports.
- HTTP 8080 returns 501 for OPTIONS and Depth: 0 PROPFIND.
- HTTPS 443 is reachable but certificate verification fails (self-signed).
  Verification was not bypassed; no credentials were transmitted.

NAS WebDAV acceptance is **not performed**, not passed. No NAS settings changed.
A different configured port/path could exist; these probes do not prove that
the NAS has no WebDAV capability. A local simulation would only test a local
server and would not certify this NAS, TLS trust or real-account behavior.

Native WebDAV feature parity remains open separately from this deferred live
test. Skipping the test does not establish implementation or full Linux parity.
