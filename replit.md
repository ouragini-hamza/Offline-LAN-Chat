# Offline LAN Chat

LocalLink is a Flutter app for discovering nearby phones and chatting directly over the same local Wi-Fi network, without an internet chat service.

## Run & Operate

- `pnpm --filter @workspace/api-server run dev` — run the API server (port 5000)
- `pnpm run typecheck` — full typecheck across all packages
- `pnpm run build` — typecheck + build all packages
- `pnpm --filter @workspace/api-spec run codegen` — regenerate API hooks and Zod schemas from the OpenAPI spec
- `pnpm --filter @workspace/db run push` — push DB schema changes (dev only)
- Required env: `DATABASE_URL` — Postgres connection string
- Flutter app source: `mobile/offline_lan_chat`; follow its README to create Android/iOS runner folders with a Flutter SDK.

## Stack

- pnpm workspaces, Node.js 24, TypeScript 5.9
- API: Express 5
- DB: PostgreSQL + Drizzle ORM
- Validation: Zod (`zod/v4`), `drizzle-zod`
- API codegen: Orval (from OpenAPI spec)
- Build: esbuild (CJS bundle)

## Where things live

- `mobile/offline_lan_chat/lib/` — Flutter UI, local history, and direct LAN discovery/messaging.
- `mobile/offline_lan_chat/README.md` — platform permissions and setup instructions.
- `artifacts/api-server/` — shared API service; the LAN chat MVP does not depend on it.

## Architecture decisions

- The chat MVP is implemented in Flutter source as requested; do not silently replace it with Expo.
- Device discovery and message delivery use local UDP broadcast and direct TCP sockets; the MVP does not route chat through the shared API.
- Message history is local SQLite. Current messages are not encrypted; only use trusted Wi-Fi until encryption is added.

## Product

- Discover phones on the same Wi-Fi, send acknowledged text messages, rename the local device, and browse locally saved conversation history.
- Planned later work from the design notes: direct file transfers, encryption, resume, groups, and previews.

## User preferences

- Keep this app in Flutter; the user chose Flutter source files over switching to Expo.

## Gotchas

- The current workspace has Dart tooling but no Flutter SDK or Flutter app preview. Generate native runner folders and run on two physical phones using the instructions in the Flutter project's README.
- IPv4 broadcast can be blocked by Wi-Fi client isolation, VPNs, or non-broadcast LAN configurations.

## Pointers

- See the `pnpm-workspace` skill for workspace structure, TypeScript setup, and package details
