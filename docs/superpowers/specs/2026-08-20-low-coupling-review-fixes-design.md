# Low-Coupling Review Fixes Design

## Goal

Resolve the review findings while preserving strict dependency direction and keeping platform-specific behavior outside application and presentation code.

## Constraints

- `lib/application/` may depend only on `lib/domain/` and other application ports.
- `lib/sync/`, `lib/data/`, and `lib/services/` implement ports but are never imported by application services.
- `lib/presentation/` consumes application ports and plain DTOs only; composition occurs in `CardoryApp`.
- iOS WidgetKit target configuration and App Group entitlements remain under `ios/`.
- Existing uncommitted work remains intact; this change adds no state-management dependency.

## Architecture

### Credential Boundary

Create an application-owned `SyncCredentialStore` port plus the credential value objects it consumes. `WorkspaceSettingsService` and `WorkspaceControllerFactory` depend on that port. The current secure storage adapter remains in `lib/sync/` and implements the port. `CardoryApp` imports the adapter and injects it at the composition root.

This reverses the current application-to-sync dependency without moving secure-storage or provider-specific implementation details into the application layer. The provider registry may continue to consume the port because infrastructure is allowed to depend inward.

The port exposes one aggregate credential record rather than independent WebDAV,
self-hosted, and S3 key writes. The secure adapter stores the aggregate under
one versioned key and reads legacy per-provider keys only for migration.
`WorkspaceSettingsService` snapshots the aggregate, writes the replacement,
then persists settings; if settings persistence fails, it restores the snapshot.
This prevents partial S3 key pairs and preserves credentials required by old
settings after a failed provider switch.

### Attachment Deletion Journal

`AppSettings` owns a local `pendingAttachmentDeletes` journal because it
already owns local synchronization state. Workspace mutations enqueue removed
attachment storage keys after the data mutation has persisted. `SyncCoordinator`
consumes this journal through its existing settings input and an
`AttachmentSyncProvider` delete operation. It deletes each remote object
idempotently and clears journal entries only after the container write succeeds.

The attachment repository also gains an orphan-pruning operation. After a remote
container replaces workspace data, the controller removes encrypted files no
longer referenced by asset metadata. Application code does not inspect remote
protocols or storage directories.

### Resource Lifecycle

`SyncProvider` becomes an owned disposable resource. Each HTTP provider closes
its client when appropriate; `SyncCoordinator` invokes disposal in a `finally`
block after every synchronization. The directory provider uses a no-op
implementation. This prevents transient provider creation from retaining socket
resources.

### Sidebar Animation

Keep the brand and item labels mounted while the sidebar changes width. Animate label opacity and width/alignment from the existing `expanded` value, ensuring collapse has a real 1-to-0 transition. The behavior remains fully local to `Sidebar`; no new interface or state is exposed.

### iOS Widget Integration

Add a `CardoryWidget` extension target to the existing Xcode project, embed it in Runner, and add matching App Group entitlements to Runner and the extension. Configure `home_widget` with the same App Group before writing widget data. The platform adapter owns this configuration; `WidgetDataService` remains the only application-facing interface.

### Documentation and Comments

Update README architecture, interface, and provider descriptions to match the extracted presentation layer, repository ports, four sync providers, attachment storage, and widget integration. Change documentation comments introduced by this work from `///` to `//` to follow the project's stated convention.

## Data Flow

`CardoryApp` creates `SecureSyncCredentialStore` -> passes it as application `SyncCredentialStore` to the controller factory and sync provider registry -> application services persist settings via the port. Flutter data mutations call `WidgetDataService`; `HomeWidgetDataService` performs iOS App Group setup and writes the payload; the WidgetKit extension reads the same group.

On asset deletion, the controller saves the data mutation, records remote object
keys in local sync settings, removes local files, and later passes those settings
to `SyncCoordinator`. The coordinator deletes journaled remote objects before
writing the new container and clears the journal only after that write succeeds.

Android widget payloads store date fields, not precomputed time-sensitive state.
The Android provider derives overdue and due-soon labels when rendering, and its
update period permits the operating system to refresh those labels while the
Flutter app is not open.

## Error Handling

- A missing or malformed secure credential remains represented as `null` through the port.
- Widget update failures remain best-effort and must not block workspace persistence.
- The iOS extension is a build-time target; entitlement mismatches are caught by Xcode signing/build validation.
- A remote attachment deletion failure keeps its storage key in the journal for the next synchronization attempt.
- A failed settings write restores the credential aggregate before reporting the original save error.

## Testing

- Unit-test `WorkspaceSettingsService` against an in-memory application credential port, proving it no longer imports infrastructure types.
- Widget-test Sidebar collapse and expansion, asserting labels remain mounted and opacity animates.
- Add source-level configuration checks for the iOS target, App Group identifiers, and Flutter adapter identifier because the Dart test runner cannot build an iOS extension on Windows.
- Test attachment delete propagation, failed credential/settings transitions, S3 aggregate writes, provider disposal, and Android date classification.
- Run focused tests, `flutter analyze`, `flutter test`, and `git diff --check`.
