# Maestro flows

End-to-end flows for the iPhone companion app.

```bash
# Build and install first (Xcode, scheme NightcapPhone, an iOS simulator),
# then:
maestro test .maestro/
```

Flows run against the stubbed `MacStateTransportClient`, so they exercise the
real UI and reducer without needing a Mac on the other end.
