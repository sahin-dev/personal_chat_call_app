# Mobile

Flutter source for the chat/call MVP.

## Commands

```powershell
flutter pub get
flutter create . --platforms android,ios
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000 --dart-define=SOCKET_URL=http://10.0.2.2:3000
```

Use `10.0.2.2` for the Android emulator. Use your computer's LAN IP address for a real phone.

## Main Packages

- `http` for REST API calls
- `socket_io_client` for messages and call signaling
- `flutter_webrtc` for audio/video calls
- `file_picker` for file sharing
- `flutter_secure_storage` for token storage
- `provider` for minimal app state
