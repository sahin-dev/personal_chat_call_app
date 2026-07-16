# Personal Chat Call App

Minimal one-to-one chat, file sharing, audio call, and video call system.

## Structure

- `backend/` - NestJS API, Socket.IO gateway, Prisma, MongoDB
- `mobile/` - Flutter app source for auth, chats, files, and WebRTC calls

## MVP Features

- Register, login, and JWT auth
- Search users
- Create direct chats
- Send text messages in real time
- Soft-delete own messages
- Upload and send files
- WebRTC audio/video calls
- Socket signaling only for calls; media is not stored by the backend

## Backend Quick Start

```powershell
cd backend
Copy-Item .env.example .env
pnpm install
pnpm prisma:generate
pnpm prisma:push
pnpm start:dev
```

Set `DATABASE_URL` in `backend/.env` to a MongoDB database. MongoDB Atlas is the easiest option. For reliable local Prisma + MongoDB development, use a MongoDB replica set.

## Flutter Quick Start

Flutter is not installed on this machine right now. Once installed:

```powershell
cd mobile
flutter pub get
flutter create . --platforms android,ios
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000 --dart-define=SOCKET_URL=http://10.0.2.2:3000
```

For a real Android device, replace `10.0.2.2` with your computer's LAN IP address.

## Call Notes

The backend forwards only signaling messages:

- `call:invite`
- `call:accept`
- `call:reject`
- `call:end`
- `webrtc:offer`
- `webrtc:answer`
- `webrtc:ice-candidate`

Audio/video media flows peer-to-peer through WebRTC. For production, add a TURN server because public STUN alone will not work on every network.
