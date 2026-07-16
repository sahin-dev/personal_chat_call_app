import { Module } from "@nestjs/common";
import { AuthModule } from "../auth/auth.module";
import { MessagesModule } from "../messages/messages.module";
import { RealtimeGateway } from "./realtime.gateway";

@Module({
  imports: [AuthModule, MessagesModule],
  providers: [RealtimeGateway],
})
export class RealtimeModule {}
