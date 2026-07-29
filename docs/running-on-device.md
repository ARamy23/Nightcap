# Running Nightcap on your own devices

The default build is offline: `MacStateTransportClient.liveValue` is a stub and
`MacStatePublisherClient.liveValue` is a no-op, matching what the App Store
listing and PRIVACY.md describe. The companion apps only talk to a real Mac in a
CloudKit build, which is opt-in and signed by your own team.

## One-time setup

```bash
export PATH="$HOME/.rbenv/versions/3.1.2/bin:$PATH"   # see docs note below
fastlane provision_icloud       # App IDs, capabilities, container, Mac profile
fastlane provision_devices      # registers attached devices, re-mints profiles
```

`provision_devices` registers every physically attached iPhone and Watch from
`devicectl`, then re-mints the profiles and **fails** if one does not carry every
attached device. The order matters: registering a device does not retro-fit it
into a profile minted earlier, so a profile fetched before registration installs
onto nothing.

Two steps Apple does not expose to automation:

- **iCloud containers** are absent from the App Store Connect API entirely — they
  live in the legacy portal, which is why this needs a `spaceauth` session.
- **Associating a container with a *Mac* App ID** is refused by Spaceship. Do it
  once in Xcode's Signing & Capabilities, or on the portal website. iPhone and
  Watch associate automatically.

## Each build

```bash
fastlane generate_cloud_project   # writes gitignored overlay + regenerates
xed .
```

The generated project sets `NIGHTCAP_CLOUDKIT` on the Mac, phone and watch
targets. That flag does three things, and all three are needed — with any one
missing the app looks like it works while being fake:

| Without it | Symptom |
|---|---|
| Transport override | Companions render canned sample apps as if they were your Mac |
| Publisher override | Mac publishes nothing; companions sit on "Waiting for your Mac" |
| Entitlement | Signs fine, finds no container at runtime — looks identical to the above |

Run the `Nightcap` scheme on your Mac first so it publishes, then `NightcapPhone`
on the device. The watch app is standalone (`WKWatchOnly`), so it installs
directly rather than riding along with the phone app.

## Devices must be connected before you touch the destination

Check first:

```bash
xcrun devicectl list devices | grep -E "Ordis|Watch"
xcrun devicectl device info details --device <UDID> | grep "Device State"
```

`available (paired)` in the list is **not** the same as reachable. The detail
view's `Device State` is the one that matters: `connected` is good,
`disconnected` or `connecting` is not.

Selecting a run destination — not merely running — for a device whose state is
not `connected` makes Xcode block indefinitely waiting for it. That wedges the
whole MCP tool service, so every later call queues behind it and times out. It
recovers on its own after several minutes; do not force-quit Xcode to clear it,
especially with another project open in a second window.

The Watch is far more prone to this than the iPhone: it drops to `disconnected`
whenever it locks. Put it on your wrist, unlocked, near the Mac, and confirm
`connected` immediately before selecting it. A cable makes the iPhone reliable;
the Watch has no such option.

## Verifying without Xcode

The app entry points can be type-checked against the SwiftPM-built modules,
which catches API mistakes without a full build:

```bash
ARGS=(); for d in Packages/*/.build/out/Products/Debug; do ARGS+=(-I "$d"); done
swiftc -typecheck -parse-as-library -sdk "$(xcrun --show-sdk-path --sdk macosx)" \
  -target arm64-apple-macos14.0 -DNIGHTCAP_CLOUDKIT "${ARGS[@]}" \
  Nightcap/NightcapApp.swift
```

Run it with and without `-DNIGHTCAP_CLOUDKIT`: both paths must compile, since the
`#if` blocks sit in shipping code.

## Ruby

fastlane is installed only under rbenv 3.1.2. `bundle exec fastlane` fails
(the Gemfile resolves against 3.4.8, which has no fastlane), and `bundle install`
fails against rubygems TLS. Export the 3.1.2 bin directory as shown above.
