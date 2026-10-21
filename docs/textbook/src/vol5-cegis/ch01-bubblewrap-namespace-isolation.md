# Chapter 1: Linux Container Namespace Isolation

**Volume V:** Grounded Verification & Autonomous CEGIS  
**GHC Note Invariant:** Note [Bubblewrap Namespace Isolation and Resource Limiting Boundaries] [ref:note-sandbox-bwrap-isolation]  
**Production Module:** [`Sandbox.Handler`](../../../../packages/gargamelle-sandbox/src/Sandbox/Handler.hs) ([Hackage](https://hackage.haskell.org/package/gargamelle-sandbox/docs/Sandbox-Handler.html))

---

## 1. Physical Isolation Boundaries

Untrusted AI-synthesized code must be isolated from the host operating system. Rather than spinning up heavyweight Docker daemons or hypervisors, Gargamelle utilizes unprivileged Linux namespaces via **Bubblewrap** (`/usr/bin/bwrap`).

Bubblewrap enforces:
- **Private Mount Namespace:** Read-only root bind-mount (`--ro-bind / /`), sterile `/tmp` (`--tmpfs /tmp`), and read-write binding strictly limited to the candidate's scratch workspace.
- **Private PID Namespace:** Synthesized code cannot see, signal, or trace host processes (`--unshare-pid`).
- **Private IPC and UTS Namespaces:** Complete isolation from host shared memory and hostname changes.
- **Resource Boundaries:** Hard execution deadlines enforced via `/usr/bin/timeout` (default: 30s) and memory caps.

---

## 2. AppArmor Unprivileged Namespace Resilience

In modern Linux distributions (such as Ubuntu 24.04), kernel restrictions restrict unprivileged user namespaces by default (`kernel.apparmor_restrict_unprivileged_userns = 1`), blocking loopback network device creation (`bwrap: loopback: Failed RTM_NEWADDR: Operation not permitted`).

As detailed in Note [Bubblewrap Namespace Isolation and Resource Limiting Boundaries] [ref:note-sandbox-bwrap-isolation], Gargamelle provides a resilient three-tier fallback:
1. Strict `--unshare-all` isolation.
2. Transparent retry with `--unshare-all --share-net` (retaining full filesystem, mount, and PID isolation while borrowing loopback).
3. Graceful fallback to scoped subprocess execution with hard timeout boundaries if user namespaces are disabled entirely.
