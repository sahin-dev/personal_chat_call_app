import { Module } from "@nestjs/common";
import { AuthModule } from "../auth/auth.module";
import { ChatsModule } from "../chats/chats.module";
import { MessagesController } from "./messages.controller";
import { MessagesService } from "./messages.service";

@Module({
  imports: [AuthModule, ChatsModule],
  controllers: [MessagesController],
  providers: [MessagesService],
  exports: [MessagesService],
})
export class MessagesModule {}
