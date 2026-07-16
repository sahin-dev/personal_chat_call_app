# Backend

NestJS backend for the chat/call MVP.

## Commands

```powershell
pnpm install
pnpm prisma:generate
pnpm prisma:push
pnpm start:dev
```

## Environment

Copy `.env.example` to `.env`, then update:

- `DATABASE_URL`
- `JWT_SECRET`
- `PUBLIC_BASE_URL`
- `CLIENT_ORIGIN`

For the included Docker MongoDB:

```txt
DATABASE_URL="mongodb://localhost:27017/personal_chat_call?replicaSet=rs0"
```

## API

- `POST /auth/register`
- `POST /auth/login`
- `GET /auth/me`
- `GET /users?query=`
- `POST /chats/direct`
- `GET /chats`
- `GET /chats/:id/messages`
- `POST /chats/:id/messages`
- `DELETE /messages/:messageId`
- `POST /messages/:messageId/read`
- `POST /files/upload`
- `GET /files/:id`
