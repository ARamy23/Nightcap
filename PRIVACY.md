# Privacy Policy

**Last updated:** July 29, 2026

Nightcap collects nothing. We operate no servers and receive no data about
you. This document exists because the Mac App Store requires a public privacy
policy URL.

## What we collect

**Nothing.** Nightcap does not collect, transmit, log, or share any user
data with us or with any third party. There are no analytics, no telemetry, no
crash reporting, no advertising identifiers, and no user accounts.

## The companion apps and iCloud

The Nightcap apps for iPhone and Apple Watch show what your Mac is doing and
let you pause or resume a watched app remotely. That requires the Mac and your
devices to exchange a small amount of information.

**This feature is off unless you turn it on.** With it disabled, Nightcap makes
no network connections at all, exactly as before.

When enabled:

- Your Mac writes a snapshot to **your own private iCloud database**, using
  Apple's CloudKit. The snapshot contains the same watched-app list already
  stored locally, which of those apps are currently running, whether your Mac
  is being kept awake, and whether it has lost its network connection.
- Your iPhone and Watch read that snapshot from the same private database.
- Requests to pause or resume an app travel the same way.

Two things worth being explicit about:

- **The data goes to your iCloud account, not to us.** It sits in the private
  database of your own account. We have no server, no access to your
  container, and no ability to read any of it.
- **It is still a network connection.** Enabling the companion apps means the
  Mac app is no longer network-free. Apple's iCloud handles the transport, and
  Apple's privacy policy governs data at rest in your account.

To stop it, sign out of iCloud or disable iCloud for Nightcap in System
Settings. Deleting the app removes its container and the snapshot with it.

## What we store locally

Nightcap stores one file on your Mac:

- `~/Library/Containers/com.abdocodes.nightcap/Data/Documents/watched-apps.json`

This file contains a list of the apps you've chosen to watch (bundle ID and
display name). It never leaves your device. macOS isolates this file inside
the app's sandbox container, accessible only to Nightcap itself and to you.

## Required-reason API declarations

Nightcap declares the following required-reason API usage in its
[`PrivacyInfo.xcprivacy`](Nightcap/PrivacyInfo.xcprivacy) manifest, per Apple
policy:

| API | Reason code | Purpose |
| --- | --- | --- |
| `NSPrivacyAccessedAPICategoryUserDefaults` | `CA92.1` | Reading the app's own preferences (transitive use via SwiftUI / TCA). |
| `NSPrivacyAccessedAPICategoryFileTimestamp` | `C617.1` | Reading file metadata of the app's own container files (the `watched-apps.json` above). |

Neither category accesses user data — both are scoped to Nightcap's own
sandbox.

## Third-party SDKs

Nightcap statically links the following open-source Swift packages, all from
[Point-Free](https://github.com/pointfreeco):

- swift-composable-architecture
- swift-dependencies
- swift-sharing
- swift-case-paths
- swift-concurrency-extras
- swift-perception
- swift-custom-dump
- swift-identified-collections
- swift-navigation
- swift-clocks
- combine-schedulers
- xctest-dynamic-overlay

None of these SDKs perform analytics, networking, or data collection.

## Children

Nightcap is not directed at children. It contains no advertising and no data
collection of any kind, so it is safe for users of any age.

## Changes to this policy

If Nightcap ever starts collecting data, this document will be updated and
the version field in the Mac App Store listing will be bumped. The change
history is publicly visible in the
[git log](https://github.com/Abdo-codes/Nightcap/commits/main/PRIVACY.md) of
this repository.

## Contact

Questions or concerns: open an issue at
[github.com/Abdo-codes/Nightcap/issues](https://github.com/Abdo-codes/Nightcap/issues).
