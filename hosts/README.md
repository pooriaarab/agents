# Host overlays

One workspace, many machines. A host overlay holds what is true about **one machine** —
addresses, key paths, account names, service paths, per-machine quirks — so the shared
rules stay portable.

```
hosts/
  <host-name>/
    rules.md        # what an agent must know before touching this machine
```

Keep an overlay in a **private** repository. A public workspace should carry the pattern,
not the addresses: an overlay names real hosts, real accounts, and real key paths, and none
of that belongs in public history. Shared rules should refer to "the active host overlay"
rather than to any machine.

An overlay earns its place by recording things that cost you a debugging session:

- how to reach the machine, and which shell a remote command actually lands in
- which services it runs, and how to check that they are alive
- what an agent must not change without being asked
- failure modes specific to this machine, with the exact error text they produce

That last one matters most. A symptom you have already diagnosed once — an error that only
appears on this machine, a job that dies with no message, a service that reports healthy
while doing nothing — is the difference between a two-minute fix and an hour of rediscovery.
Write down the error string, not just the cause.
