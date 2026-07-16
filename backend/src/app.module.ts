import { Module } from "@nestjs/common";
import { ConfigModule } from "@nestjs/config";
import { AuthModule } from "./modules/auth/auth.module";
import { ChatsModule } from "./modules/chats/chats.module";
import { FilesModule } from "./modules/files/files.module";
import { MessagesModule } from "./modules/messages/messages.module";
import { PrismaModule } from "./modules/prisma/prisma.module";
import { RealtimeModule } from "./modules/realtime/realtime.module";
import { UsersModule } from "./modules/users/users.module";

@Module({
  imports: [
    ConfigModule.forRoot({ isGlobal: true }),
    PrismaModule,
    AuthModule,
    UsersModule,
    ChatsModule,
    MessagesModule,
    FilesModule,
    RealtimeModule,
  ],
})
export class AppModule {}
