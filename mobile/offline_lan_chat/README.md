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
