# Implementation checklist

- [x] Fork and preserve upstream remote, dedicated feature branch; rebase from 1.1.2 to the recorded upstream master snapshot completed.
- [x] Pure continuity tracker with snapshot, epoch and lifecycle tests.
- [x] IMK probe, native text widget tests, context event bridge and versioned Lua handshake.
- [x] Detect otherwise unobserved direct commits using a commit receipt.
- [x] Real librime/Lua + NSTextView integration harness with isolated fixture dictionary.
- [x] Development bundle isolation, build tooling and rollback instructions.
- [ ] Manual OS input-source/application capability matrix and performance measurements: requires installation/activation outside this repository.
- [ ] Broad daily-use rollout: only after those app-specific checks.

The code is implemented locally; the unchecked rollout items are not represented as completed tests. Original approved design: [DESIGN.md](DESIGN.md). The bridge wire format was simplified from draft JSON to strictly delimited versioned fields, and unobserved outputs use a checksum receipt, as documented in README.md.
