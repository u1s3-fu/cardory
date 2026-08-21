# Low-Coupling Review Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Repair the reviewed synchronization, widget, dependency-direction, and documentation defects without allowing application code to depend on transport or secure-storage implementations.

**Architecture:** Application owns ports, credential DTOs, and local sync metadata. Sync, data, and services implement those ports; `CardoryApp` is the only composition root. Pending attachment deletes are persisted with other local sync state and executed only by synchronization adapters.

**Tech Stack:** Flutter/Dart, flutter_test, flutter_secure_storage, http, Android AppWidget, iOS WidgetKit/Xcode.

**Spec:** `docs/superpowers/specs/2026-08-20-low-coupling-review-fixes-design.md`

## Global Constraints

- `lib/application/` depends only on `lib/domain/` and application ports.
- `lib/sync/`, `lib/data/`, and `lib/services/` implement ports and are not imported by application services.
- Keep secure-storage, HTTP, Android, and iOS details outside application and presentation layers.
- Preserve existing uncommitted work and create no commit in this shared dirty worktree.
- Use `//`, not `///`, for newly touched Dart comments.

---

### Task 1: Aggregate Credential Port

**Files:**
- Create: `lib/application/sync_credentials.dart`
- Modify: `lib/application/workspace_settings_service.dart`, `lib/application/workspace_controller_factory.dart`
- Modify: `lib/sync/sync_credentials.dart`, `lib/sync/sync_provider_registry.dart`
- Modify: `lib/presentation/cardory_app.dart`, `lib/presentation/pages/home_page.dart`, `lib/presentation/pages/settings_page.dart`
- Test: `test/workspace_settings_service_test.dart`

**Interfaces:** Produces `SyncCredentialStore.read(): Future<SyncCredentials>` and `write(SyncCredentials): Future<void>` in application. `SyncCredentials` contains nullable `WebDavCredentials`, self-hosted token, and `S3Credentials`.

- [ ] Write a failing test proving that a settings-write failure restores the previous credential aggregate.

```dart
await expectLater(service.apply(nextSettings, credentials: nextCredentials), throwsStateError);
expect((await store.read()).webDav?.password, 'old-password');
```

- [ ] Run `flutter test --no-pub test/workspace_settings_service_test.dart`; expect a compile failure because the aggregate port does not exist.
- [ ] Add aggregate DTOs and port in application; make the sync secure-store adapter serialize the aggregate under one versioned key and migrate legacy keys after a successful aggregate write.
- [ ] Make `WorkspaceSettingsService` read the previous aggregate, write the replacement, save settings, and restore the previous aggregate if saving settings fails.
- [ ] Re-run `flutter test --no-pub test/workspace_settings_service_test.dart`; expect PASS.

### Task 2: Provider Ownership and S3 Regression Tests

**Files:**
- Modify: `lib/sync/sync_provider.dart`, `lib/sync/sync_coordinator.dart`
- Modify: `lib/sync/directory_sync_provider.dart`, `lib/sync/webdav_sync_provider.dart`, `lib/sync/self_hosted_api_sync_provider.dart`, `lib/sync/s3_sync_provider.dart`
- Create: `test/s3_sync_provider_test.dart`
- Modify: `test/sync_coordinator_test.dart`

**Interfaces:** Produces `Future<void> dispose()` on `SyncProvider`; `SyncCoordinator` owns and disposes a provider created for one synchronization.

- [ ] Write failing tests that assert a provider is disposed after synchronization and an S3 conditional write sends `if-match` plus an AWS4 authorization header.

```dart
await coordinator.synchronize(const AppSettings(syncProvider: SyncProviderType.directory));
expect(provider.disposed, isTrue);
expect(request.headers['if-match'], 'etag-1');
```

- [ ] Run `flutter test --no-pub test/sync_coordinator_test.dart test/s3_sync_provider_test.dart`; expect compile failure.
- [ ] Add the disposal contract, close only owned HTTP clients, use a no-op directory implementation, and invoke disposal in `SyncCoordinator`'s `finally` block.
- [ ] Add deterministic S3 tests with a fixed clock and mock client for path encoding, authorization, conditional writes, and attachment streaming.
- [ ] Re-run `flutter test --no-pub test/sync_coordinator_test.dart test/s3_sync_provider_test.dart`; expect PASS.

### Task 3: Attachment Deletion Journal

**Files:**
- Modify: `lib/domain/app_settings.dart`, `lib/application/attachment_repository.dart`, `lib/application/workspace_controller.dart`
- Modify: `lib/sync/sync_provider.dart`, `lib/sync/sync_coordinator.dart`
- Modify: `lib/data/attachment_store.dart`, all attachment-capable sync providers
- Test: `test/workspace_controller_test.dart`, `test/sync_coordinator_test.dart`, `test/directory_sync_provider_test.dart`, `test/self_hosted_api_sync_provider_test.dart`

**Interfaces:** Produces `AppSettings.pendingAttachmentDeletes`, `AttachmentSyncProvider.deleteFile(String)`, and `AttachmentRepository.prune(Set<String>)`.

- [ ] Write failing tests that expect a removed storage key to be deleted remotely and retained in the journal when deletion or container write fails.

```dart
expect(provider.deletedFiles, ['attachments/v1/removed.cardory-attachment']);
expect(settings.pendingAttachmentDeletes, isEmpty);
```

- [ ] Run `flutter test --no-pub test/workspace_controller_test.dart test/sync_coordinator_test.dart`; expect compile failure.
- [ ] Persist removed storage keys in `AppSettings`; have the coordinator delete journaled remote objects idempotently before writing the container and clear keys only after a successful write.
- [ ] Have the attachment store prune unreferenced local encrypted objects after authoritative data loads; preserve active temporary files.
- [ ] Implement `deleteFile` for directory, WebDAV, self-hosted, and S3 providers, mapping a missing remote file to success.
- [ ] Re-run `flutter test --no-pub test/workspace_controller_test.dart test/sync_coordinator_test.dart test/directory_sync_provider_test.dart test/self_hosted_api_sync_provider_test.dart`; expect PASS.

### Task 4: Native Widget Delivery and Time Semantics

**Files:**
- Modify: `lib/presentation/widgets/sidebar.dart`, `lib/services/home_widget_data_service.dart`
- Modify: `android/app/src/main/kotlin/com/cardory/app/CardoryWidgetProvider.kt`, `android/app/src/main/res/xml/cardory_widget_info.xml`
- Modify: `ios/Runner.xcodeproj/project.pbxproj`, `ios/CardoryWidget/CardoryWidget.swift`, `ios/CardoryWidget/Info.plist`
- Create: `ios/Runner/Runner.entitlements`, `ios/CardoryWidget/CardoryWidget.entitlements`
- Test: `test/widget_test.dart`

**Interfaces:** Sidebar labels stay mounted while opacity changes. Widget payload carries dates; native providers compute current time-sensitive labels.

- [ ] Write failing widget tests that find a sidebar label after collapse and source-level tests that require the shared App Group in Runner, extension, and Flutter adapter configuration.

```dart
await tester.pumpWidget(sidebarHarness(expanded: false));
expect(find.text('看板'), findsOneWidget);
expect(File('ios/Runner/Runner.entitlements').readAsStringSync(), contains('group.com.cardoryapp.widget'));
```

- [ ] Run `flutter test --no-pub test/widget_test.dart`; expect these assertions to fail.
- [ ] Keep label widgets mounted with animated opacity and constrained width.
- [ ] Add an embedded `CardoryWidget` extension target and matching entitlements; configure `home_widget` to use `group.com.cardoryapp.widget` before saving data.
- [ ] Send end-date values to Android, calculate overdue/due-soon at render time, and use a valid periodic widget refresh interval.
- [ ] Re-run `flutter test --no-pub test/widget_test.dart`; expect PASS.

### Task 5: Documentation and Final Validation

**Files:**
- Modify: `README.md`, `CHANGELOG.md`
- Modify: touched Dart comments that still use `///`

- [ ] Document the extracted presentation layer, four sync providers, aggregate credential port, attachment deletion retry behavior, and integrated mobile widgets.
- [ ] Run `git diff --check HEAD`; expect no whitespace errors.
- [ ] Run `flutter analyze --no-pub` and `flutter test --no-pub`; expect no analyzer errors or test failures.
- [ ] Run `git status --short` and `git diff --stat HEAD`; verify only scoped source, native configuration, tests, and documentation changed.
