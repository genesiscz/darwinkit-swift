# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

DarwinKit is a hybrid Swift/TypeScript monorepo that exposes Apple's on-device ML frameworks (NLP, Vision, CoreML, Speech, Sound, LLM, Contacts, Calendar, Reminders, Notifications, etc.) via JSON-RPC over stdio. It's a fork of [0xMassi/darwinkit](https://github.com/0xMassi/darwinkit) with extended functionality, published as `@genesiscz/darwinkit` on npm.

## Build Commands

### Swift (the CLI server)
```bash
cd packages/darwinkit-swift
swift build                                    # debug build
swift build -c release --arch arm64              # release binary
swift test                                     # run all tests
swift test --filter DarwinKitCoreTests.NLPHandlerTests  # single test class
```

Binary output: `packages/darwinkit-swift/.build/arm64-apple-macosx/release/darwinkit`

### TypeScript SDK
```bash
cd packages/darwinkit
bun install
bun run build    # builds ESM + CJS via tsup → dist/
bun run dev      # watch mode
```

### Full local build (binary + SDK + .app bundle)
```bash
./release.sh --build-only
```

### Release

```bash
./release.sh <version>              # full release: bump, build, tag, push, GH release → npm
./release.sh <version> --no-push    # bump, build, tag locally — don't push or create GH release
./release.sh --build-only           # local binary + SDK build only (no version change)
```

**Flow** (`./release.sh 0.7.0`):
1. Pre-flight: must be on `main`, working tree clean (except `packages/darwinkit/package.json`).
2. Bumps `packages/darwinkit/package.json` to the new version, commits `chore: bump version to X.Y.Z`.
3. Builds arm64 release binary (`swift build -c release --arch arm64`).
4. Creates `vX.Y.Z` git tag, pushes commit + tag to `origin/main`.
5. Tarballs the binary as `darwinkit-macos-arm64.tar.gz`, creates a GitHub release with auto-generated notes.
6. GitHub Actions workflow `.github/workflows/publish-npm.yml` triggers on release creation and runs `npm publish --provenance --access public` via OIDC trusted publishing (no `NPM_TOKEN` needed; npm ≥ 11.5.1 required for scoped-package OIDC).

**Resume**: if `vX.Y.Z` already exists at HEAD with matching `package.json`, the script skips bump+tag and continues from the tarball/release step. Useful if a previous run failed mid-way.

**Verify after release**:
```bash
gh release view v0.7.0 --repo genesiscz/darwinkit-swift
gh run list --repo genesiscz/darwinkit-swift --limit 3   # check "Publish to npm" run
npm view @genesiscz/darwinkit version                    # should show new version
```

### Upstream sync
```bash
./sync.sh         # rebase onto 0xMassi/darwinkit, create PR
./sync.sh --dry   # preview only
```

## Architecture

```
Your App ──stdin JSON-RPC──▶ darwinkit (Swift CLI) ──▶ Apple Frameworks
           ◀──stdout JSON-RPC──
```

### Monorepo layout
- `packages/darwinkit-swift/` — Swift package (the server)
- `packages/darwinkit/` — TypeScript SDK (the client)
- Root `package.json` — workspace coordination

### Swift side (`packages/darwinkit-swift/`)
- **`Sources/DarwinKit/`** — CLI entrypoint with `serve` (default) and `query` subcommands
- **`Sources/DarwinKitCore/`** — Core library:
  - `Server/` — `JsonRpcServer` reads NDJSON from stdin, `MethodRouter` dispatches to handlers
  - `Handlers/` — One handler per domain (NLPHandler, VisionHandler, etc.), each registers methods with the router
  - `Providers/` — Framework adapters that do the actual Apple API calls
- **`Tests/DarwinKitCoreTests/`** — Unit tests per handler

**Key pattern:** Each domain follows Handler → Provider. The handler parses JSON-RPC params and calls the provider. The provider wraps Apple framework APIs. Handlers register themselves via `router.register(SomeHandler())` in `DarwinKit.swift:buildRouter()`.

### TypeScript side (`packages/darwinkit/`)
- **`src/client.ts`** — `DarwinKit` class with namespace properties (`.nlp`, `.vision`, `.coreml`, etc.)
- **`src/namespaces/`** — Typed wrappers per domain, each calls `this.client.request(method, params)`
- **`src/transport.ts`** — Spawns the Swift binary as a child process, manages stdio pipes
- **`src/binary.ts`** — Binary resolution: bundled → PATH → cached → download from GitHub releases → build from source
- **`src/types.ts`** — TypeScript types for all ~100 JSON-RPC methods

### Capability system
`system.capabilities` returns all available methods with OS availability info. Some providers have version-gated alternatives (e.g., `UnavailableTranslationProvider` for macOS <15).

## Key Dependencies

**Swift:** swift-argument-parser (CLI), swift-embeddings (CoreML embeddings). Minimum macOS 14, Swift 5.9.

**TypeScript:** tar (release tarballs). Published as `@genesiscz/darwinkit`. Node 18+.

## Git Remotes

- `origin` → `genesiscz/darwinkit-swift` (this fork)
- `original` → `0xMassi/darwinkit` (upstream)

## Conventions

- JSON-RPC methods are namespaced: `domain.action` (e.g., `nlp.embed`, `vision.ocr`)
- Swift errors are wrapped in `JsonRpcError` for consistent client-side handling
- The `.app` bundle (created during release) is required for notification permissions via `UNUserNotificationCenter`
- Provider availability is checked at registration time; unavailable providers return clear error codes
