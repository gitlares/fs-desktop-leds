# Privacy

FS Desktop LEDs processes lighting inputs on your Mac.

- **Bluetooth:** stores the selected device identifier and protocol locally.
- **Screen and audio:** calculates colors from small frames and short audio buffers.
  Samples are discarded after analysis. No media files are saved.
- **Notifications:** inspects accessibility roles in Notification Center. It does
  not read notification titles or message bodies.
- **Preferences:** selected modes, brightness and schedules stay on your Mac.
- **Diagnostics:** a bounded local log may contain Bluetooth device identifiers.
  It is not uploaded. Redact identifiers before sharing it publicly.
- **Updates:** Sparkle is started when you choose **Check for Updates…**. It requests
  the update feed from GitHub Pages and downloads an update from GitHub only when
  you choose to install it. Automatic checks and downloads are off. System-profile
  reporting is disabled. GitHub receives the normal request metadata, including
  your IP address and the app/updater version in the user agent.
- **Network:** there is no telemetry, analytics or media upload. Lighting control
  stays local. Help and donation actions open external sites in your browser.

The landing page has no analytics, cookies, third-party fonts or tracking scripts.
GitHub hosts the site and downloads. PayPal handles optional donations under its
own privacy policy. Visiting those services is subject to their policies.

Revoke permissions in System Settings → Privacy & Security. Disable notification
lights to stop Accessibility polling. Quitting stops media capture.
