# Code Style Guide

This document describes the code style conventions for this repository. It is a living document: if you believe a rule is outdated or missing, open an issue or a PR to update it.

## Language

- All code, comments, and commit messages MUST be written in English.
- Documentation is written in English as the source of truth; translated copies (e.g. `CONTRIBUTING.zh-CN.md`) are permitted.
- User-facing strings (UI text, notifications, etc.) MAY be localized. Keep the source strings in English and use the project's localization mechanism.

## General

- Prefer code that is easy to read and understand over clever or compact code.
- Add proper comments to explain non-trivial, complicated or unusual practices.
- DO NOT add comments to common and trivial stuff.
- Use explicit, descriptive names; avoid abbreviations.
- Do not add comments that restate what the code does. Comment on the "why" when it is not obvious.
- Keep changes focused: do not mix refactoring with feature work in the same PR.

## Android app (`android/`, Kotlin)

- Follow the official [Kotlin coding conventions](https://kotlinlang.org/docs/coding-conventions.html).
- Package root is `info.skyblond.nsp`; keep the folder layout under `android/app/src/main/java/` in sync with the package structure.
- UI is built with Jetpack Compose and Material 3. Follow common Compose conventions: state hoisting, `StateFlow` for observable state, single `Activity`.
- Use `data class` for data holders and `sealed class` for states and events.
- Prefer explicit null handling over unguarded `!!` or unchecked casts.
- Unit tests live in `android/app/src/test/` and use JUnit.

## iOS app (`ios/`, Swift / SwiftUI)

Follow the existing conventions in `ios/NSG/`:

- Use 4-space indentation, keep imports at the top of each file, and separate methods with a blank line.
- Use PascalCase for types and camelCase for properties, methods, and local variables. Name Swift files after their primary type.
- Prefer `let` for values that do not change. Use optionals and explicit error handling instead of force unwrapping or forced casts.
- Define SwiftUI views as types conforming to `View`, with their interface in `body`. Split larger views into focused subviews or computed properties.
- Use `@State private var` for view-owned state and `@Environment` for environment values. Keep shared service state in `@Observable` types, following the existing app and camera services.
- Use `@MainActor` for UI-facing services and state. Prefer `async` / `await`, structured concurrency, and asynchronous sequences over Combine; cancel tasks and release sessions when their work ends.
- Keep UI, app coordination, Bluetooth transport, camera protocol logic, persistence, and location processing in their existing areas. Keep protocol encoding and validation independent of views and hardware access.
- Unit tests live in `ios/NSGTests/` and use Swift Testing. Mirror the source responsibilities and use injected camera transports, location sources, schedulers, and isolated UserDefaults suites so unit tests can run on a simulator without camera hardware. See [the test guide](ios/NSGTests/README.md).
- Use XCUIAutomation for UI tests when adding them, and follow the existing accessibility identifier conventions for interactive controls.

## ESP32 firmware (`esp32/`, C++ / Arduino)

Follow the existing conventions in `esp32/src/`:

- Files and classes use PascalCase (e.g. `Config.h`, `NikonBLEClient.h`).
- Methods and local variables use camelCase (e.g. `doHandshake`, `getDevice`).
- Build flags and configuration macros use UPPER_SNAKE_CASE (e.g. `UBLOX_GNSS_RX_PIN`).
- Use `#ifndef` / `#define` / `#endif` include guards.
- Namespaces are PascalCase (e.g. `namespace Config`).
- Classes that own unique resources are explicitly declared non-copyable (and non-movable if applicable).
- Prefer the Arduino framework and `std::` types as used in the existing code.
- Unit tests live in `esp32/test/` and run in the `native` environment.

## Commit messages

- Write commit messages in English, in the imperative mood ("fix ...", "add ...", "do not ...").
- Keep the subject concise (ideally under 72 characters); add a body for non-obvious changes.

## Enforcement

Automated enforcement (e.g. ktlint, clang-format, spotless) is not set up yet. Until then, these rules are enforced by code review. Whether to add automated tooling is tracked in issue #17.
