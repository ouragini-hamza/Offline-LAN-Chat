# LocalLink — offline LAN chat

LocalLink is a Flutter source project for discovering nearby phones and exchanging text messages directly over the same Wi-Fi network. It does not use an internet service or a chat server. Conversation history is stored on the device in SQLite.

## Current scope

- IPv4 UDP broadcast discovery while the app is open.
- Direct TCP text messages with a delivery acknowledgement.
- Local conversation history.
- Rename this phone from the app.

File transfer, end-to-end encryption, background discovery, and group chat are not implemented yet. **Messages in this version are not encrypted. Use only on a trusted local network and do not send sensitive content.**

## Create the native platform folders

This project contains the Flutter app source and package manifest. Generate Android and iOS runner projects with a Flutter SDK, then copy their platform folders into this directory:

```sh
flutter create --empty \
  --platforms=android,ios \
  --project-name offline_lan_chat \
  --org app.locallink \
  /tmp/offline_lan_chat_runner

cp -R /tmp/offline_lan_chat_runner/android .
cp -R /tmp/offline_lan_chat_runner/ios .
flutter pub get
```

Before running on a device, add local-network permissions:

- **Android** — in `android/app/src/main/AndroidManifest.xml`, inside the `<manifest>` element and before `<application>`, add:

  ```xml
  <uses-permission android:name="android.permission.INTERNET" />
  <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
  <uses-permission android:name="android.permission.CHANGE_WIFI_MULTICAST_STATE" />
  ```

- **iOS** — in `ios/Runner/Info.plist`, add this inside the top-level `<dict>`:

  ```xml
  <key>NSLocalNetworkUsageDescription</key>
  <string>LocalLink uses your local network to find nearby phones and deliver messages directly.</string>
  ```

Run on two physical phones connected to the same Wi-Fi network:

```sh
flutter run
```

The app needs to remain open on both phones. Wi-Fi networks with client isolation enabled may block peer-to-peer traffic. This initial implementation uses IPv4 broadcast and will not discover devices across separate networks or VPNs.


## Security and reliability notes

- Discovery announcements are validated for device ID format, display-name length, and valid TCP port before a peer is added.
- Incoming messages are accepted only when the sender ID, announced name, and source LAN address match a recently discovered peer. This is a consistency check, **not cryptographic authentication**: a device on the same network may still spoof discovery traffic.
- TCP messages and acknowledgements are currently **not encrypted or cryptographically authenticated**. Do not use this MVP on public/shared Wi-Fi or send passwords, private files, or other sensitive information. A production release should add authenticated key exchange and end-to-end encryption.
- Chat history loading merges with messages that arrive while the database query is running, preventing newly received messages from disappearing from the visible conversation.
- Network delivery failures are shown as `failed`; local database errors are surfaced separately rather than being mistaken for network failures.

## Troubleshooting

1. Install/run the app on two physical phones and keep it open on both.
2. Connect both phones to the same Wi-Fi network; guest networks and campus/public Wi-Fi may block device-to-device traffic through client isolation.
3. Allow local network access when prompted on iOS and verify the Android internet/network permissions described above.
4. If a phone does not appear, use the app's discovery refresh and wait a few seconds for the next UDP announcement.
5. Delivery acknowledgements confirm that the receiving app saved the message; they do not prove that a human has read it.

## Validation

From `mobile/offline_lan_chat`, run:

```sh
flutter pub get
flutter analyze
flutter test
```

Run the app on two physical devices to verify discovery, send/receive, offline history, and delivery-failure behavior. The current project may require generating native `android/` and `ios/` folders first, as described above.
