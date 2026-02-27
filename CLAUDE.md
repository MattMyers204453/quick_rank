# quick_rank

Flutter client for SmashRank (iOS, Android, Web). See `../CLAUDE.md` for full project architecture.

## Commands

```bash
# Run on connected device/simulator
flutter run

# Run on specific device
flutter run -d <device_id>

# List available devices
flutter devices

# Build iOS
flutter build ios

# Build Android APK
flutter build apk

# Run tests
flutter test

# Clean build artifacts
flutter clean && flutter pub get
```

## Project Structure

```
lib/
├── main.dart                          # App entry point
└── src/
    ├── app.dart                       # Auth-aware routing (LoginScreen vs MainNavigationShell)
    ├── models/
    │   └── player.dart                # Player model with fromJson
    ├── services/
    │   ├── auth_service.dart          # JWT management, secure storage, auto-refresh, auth state stream
    │   ├── match_service.dart         # WebSocket STOMP + HTTP match operations
    │   └── api_service.dart           # Pool check-in/search HTTP calls
    ├── screens/
    │   ├── login_screen.dart          # Login/Register UI with toggle
    │   ├── opponent_search_screen.dart # Check-in, search, challenge flow
    │   └── match_screen.dart          # Active match: report, confirm, rematch
    ├── widgets/
    │   └── main_navigation_shell.dart # Tab navigation + logout + username in AppBar
    └── util/
        └── characters_util.dart       # Full SSBU roster (89+ characters) with icon asset paths
```

## Key Services

### AuthService (singleton)
- Stores tokens in `flutter_secure_storage` (iOS Keychain / Android EncryptedSharedPreferences)
- Exposes auth state via `Stream` — `app.dart` uses `StreamBuilder` to switch between login and main UI
- Auto-refreshes on 401 responses
- Provides `accessToken`, `userId`, `username` getters

### MatchService (singleton)
- Manages STOMP WebSocket connection (`stomp_dart_client`)
- Connects with `?token=<JWT>` query param
- Subscribes to `/user/queue/invites` and `/user/queue/match-updates`
- HTTP calls for invite, accept, decline, report, confirm, rematch — all with Bearer auth headers
- Exposes match state updates via streams

### ApiService
- Pool operations: check-in, check-out, search
- All requests include `Authorization: Bearer <token>` header via `_authHeaders` getter

## Key Patterns

- **Singleton services** — `AuthService` and `MatchService` are instantiated once and shared
- **Stream-based state** — Auth state and match updates flow via Dart `Stream`/`StreamBuilder`
- **No state management library** — Currently uses built-in streams and `setState`
- **Auth-first routing** — `app.dart` gates the entire app behind auth state; unauthenticated → LoginScreen

## Dependencies

- `http: ^1.2.0` — HTTP client
- `stomp_dart_client: ^2.0.0` — STOMP over WebSocket
- `flutter_secure_storage: ^9.2.4` — Encrypted token storage
- `google_fonts: ^8.0.0` — Typography

## Backend Connection

- **Production:** Railway URL (configured in services)
- **Local dev:** `localhost:8080` (or `10.0.2.2:8080` from Android emulator)
- Currently requires manual URL switching by commenting/uncommenting. Phase 5 introduces `AppConfig` class with compile-time environment switching.

## Gotchas

- **No `AppConfig` yet** — Base URLs are hardcoded in service files. Phase 5 adds environment-based config.
- **Player model is minimal** — `Player.fromJson` defaults missing fields; the API contract is still evolving.
- **Character icons** — 89+ characters mapped in `characters_util.dart`. Asset paths use internal codenames (e.g., `gaogaen.png` for Incineroar, `packun_flower.png` for Piranha Plant).
- **WebSocket reconnection** — Not yet robust. Robustness Phase will add automatic resync on reconnect and app resume.
- **No offline handling** — App assumes network connectivity. No queuing or graceful degradation yet.