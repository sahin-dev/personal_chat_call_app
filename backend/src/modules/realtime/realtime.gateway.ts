import { Logger } from "@nestjs/common";
import { JwtService } from "@nestjs/jwt";
import {
  ConnectedSocket,
  MessageBody,
  OnGatewayConnection,
  OnGatewayDisconnect,
  SubscribeMessage,
  WebSocketGateway,
  WebSocketServer,
} from "@nestjs/websockets";
import { MessageType, ReceiptStatus } from "@prisma/client";
import { Server, Socket } from "socket.io";
import { PrismaService } from "../prisma/prisma.service";
import { MessagesService } from "../messages/messages.service";

type SocketUser = {
  id: string;
  email: string;
  name: string;
};

type AuthenticatedSocket = Socket & {
  data: {
    user?: SocketUser;
  };
};

type SendMessagePayload = {
  chatId: string;
  type: MessageType;
  text?: string;
  fileId?: string;
  clientId?: string;
};

type CallPayload = {
  receiverId: string;
  callId: string;
  type?: "AUDIO" | "VIDEO";
  offer?: unknown;
  answer?: unknown;
  candidate?: unknown;
};

@WebSocketGateway({
  cors: {
    origin: process.env.CLIENT_ORIGIN || "*",
    credentials: true,
  },
})
export class RealtimeGateway
  implements OnGatewayConnection, OnGatewayDisconnect
{
  @WebSocketServer()
  server: Server;

  private readonly logger = new Logger(RealtimeGateway.name);
  private readonly userSockets = new Map<string, Set<string>>();

  constructor(
    private readonly jwtService: JwtService,
    private readonly prisma: PrismaService,
    private readonly messagesService: MessagesService,
  ) {}

  async handleConnection(socket: AuthenticatedSocket) {
    try {
      const token = this.extractToken(socket);
      const payload = await this.jwtService.verifyAsync<{ sub: string }>(token);
      const user = await this.prisma.user.findUnique({
        where: { id: payload.sub },
        select: { id: true, email: true, name: true },
      });

      if (!user) {
        socket.disconnect(true);
        return;
      }

      socket.data.user = user;
      await socket.join(this.userRoom(user.id));

      const sockets = this.userSockets.get(user.id) ?? new Set<string>();
      const wasOffline = sockets.size === 0;
      sockets.add(socket.id);
      this.userSockets.set(user.id, sockets);

      const chats = await this.prisma.chat.findMany({
        where: { participantIds: { has: user.id } },
        select: { id: true },
      });
      await Promise.all(
        chats.map((chat) => socket.join(this.chatRoom(chat.id))),
      );

      const delivered = await this.messagesService.markPendingDelivered(
        user.id,
      );
      const deliveredBySender = new Map<string, string[]>();
      for (const receipt of delivered) {
        const messageIds =
          deliveredBySender.get(receipt.message.senderId) ?? [];
        messageIds.push(receipt.messageId);
        deliveredBySender.set(receipt.message.senderId, messageIds);
      }
      for (const [senderId, messageIds] of deliveredBySender) {
        this.server.to(this.userRoom(senderId)).emit("messages:receipts", {
          messageIds,
          userId: user.id,
          status: ReceiptStatus.DELIVERED,
        });
      }

      socket.emit("presence:sync", {
        userIds: Array.from(this.userSockets.keys()),
      });
      socket.emit("socket:ready", { userId: user.id });
      if (wasOffline) {
        socket.broadcast.emit("user:online", { userId: user.id });
      }
    } catch (error) {
      this.logger.warn(`Socket auth failed: ${(error as Error).message}`);
      socket.disconnect(true);
    }
  }

  handleDisconnect(socket: AuthenticatedSocket) {
    const userId = socket.data.user?.id;
    if (!userId) return;

    const sockets = this.userSockets.get(userId);
    sockets?.delete(socket.id);
    if (sockets && sockets.size > 0) return;

    this.userSockets.delete(userId);
    socket.broadcast.emit("user:offline", { userId });
  }

  @SubscribeMessage("chat:join")
  async joinChat(
    @ConnectedSocket() socket: AuthenticatedSocket,
    @MessageBody() payload: { chatId: string },
  ) {
    const user = this.requireUser(socket);
    const chat = await this.prisma.chat.findFirst({
      where: { id: payload.chatId, participantIds: { has: user.id } },
      select: { id: true },
    });

    if (chat) {
      await socket.join(this.chatRoom(chat.id));
      socket.emit("chat:joined", { chatId: chat.id });
    }
  }

  @SubscribeMessage("message:send")
  async sendMessage(
    @ConnectedSocket() socket: AuthenticatedSocket,
    @MessageBody() payload: SendMessagePayload,
  ) {
    try {
      const user = this.requireUser(socket);
      let message = await this.messagesService.createMessage(
        payload.chatId,
        user.id,
        {
          type: payload.type,
          text: payload.text,
          fileId: payload.fileId,
          clientId: payload.clientId,
        },
      );

      const participantIds = await this.messagesService.getChatParticipantIds(
        payload.chatId,
      );
      const onlineRecipients = participantIds.filter(
        (id) => id !== user.id && this.userSockets.has(id),
      );
      if (onlineRecipients.length > 0) {
        await Promise.all(
          onlineRecipients.map((id) =>
            this.messagesService.markDelivered(message.id, id),
          ),
        );
        message = await this.messagesService.getMessage(message.id);
      }
      this.server
        .to(participantIds.map((id) => this.userRoom(id)))
        .emit("message:new", { message, clientId: payload.clientId });

      return { ok: true, message };
    } catch (error) {
      return this.toError(error);
    }
  }

  @SubscribeMessage("message:delete")
  async deleteMessage(
    @ConnectedSocket() socket: AuthenticatedSocket,
    @MessageBody() payload: { messageId: string },
  ) {
    try {
      const user = this.requireUser(socket);
      const message = await this.messagesService.deleteMessage(
        payload.messageId,
        user.id,
      );
      this.server
        .to(this.chatRoom(message.chatId))
        .emit("message:deleted", { message });

      return { ok: true, message };
    } catch (error) {
      return this.toError(error);
    }
  }

  @SubscribeMessage("message:read")
  async readMessage(
    @ConnectedSocket() socket: AuthenticatedSocket,
    @MessageBody() payload: { messageId: string; chatId: string },
  ) {
    try {
      const user = this.requireUser(socket);
      const receipt = await this.messagesService.markRead(
        payload.messageId,
        user.id,
      );
      this.server.to(this.chatRoom(payload.chatId)).emit("messages:receipts", {
        messageIds: [payload.messageId],
        userId: user.id,
        status: receipt.status,
      });
      return { ok: true, receipt };
    } catch (error) {
      return this.toError(error);
    }
  }

  @SubscribeMessage("chat:read")
  async readChat(
    @ConnectedSocket() socket: AuthenticatedSocket,
    @MessageBody() payload: { chatId: string },
  ) {
    try {
      const user = this.requireUser(socket);
      const result = await this.messagesService.markChatRead(
        payload.chatId,
        user.id,
      );
      this.server.to(this.chatRoom(payload.chatId)).emit("messages:receipts", {
        messageIds: result.messageIds,
        userId: user.id,
        status: ReceiptStatus.READ,
      });
      return { ok: true, result };
    } catch (error) {
      return this.toError(error);
    }
  }

  @SubscribeMessage("typing:start")
  typingStart(
    @ConnectedSocket() socket: AuthenticatedSocket,
    @MessageBody() payload: { chatId: string },
  ) {
    const user = this.requireUser(socket);
    socket.to(this.chatRoom(payload.chatId)).emit("typing:start", {
      chatId: payload.chatId,
      userId: user.id,
    });
  }

  @SubscribeMessage("typing:stop")
  typingStop(
    @ConnectedSocket() socket: AuthenticatedSocket,
    @MessageBody() payload: { chatId: string },
  ) {
    const user = this.requireUser(socket);
    socket.to(this.chatRoom(payload.chatId)).emit("typing:stop", {
      chatId: payload.chatId,
      userId: user.id,
    });
  }

  @SubscribeMessage("call:invite")
  callInvite(
    @ConnectedSocket() socket: AuthenticatedSocket,
    @MessageBody() payload: CallPayload,
  ) {
    const caller = this.requireUser(socket);
    this.server.to(this.userRoom(payload.receiverId)).emit("call:invite", {
      ...payload,
      caller,
    });
  }

  @SubscribeMessage("call:accept")
  callAccept(
    @ConnectedSocket() socket: AuthenticatedSocket,
    @MessageBody() payload: { callerId: string; callId: string },
  ) {
    const receiver = this.requireUser(socket);
    this.server.to(this.userRoom(payload.callerId)).emit("call:accept", {
      callId: payload.callId,
      receiver,
    });
  }

  @SubscribeMessage("call:reject")
  callReject(
    @ConnectedSocket() socket: AuthenticatedSocket,
    @MessageBody() payload: { callerId: string; callId: string },
  ) {
    const receiver = this.requireUser(socket);
    this.server.to(this.userRoom(payload.callerId)).emit("call:reject", {
      callId: payload.callId,
      receiverId: receiver.id,
    });
  }

  @SubscribeMessage("call:end")
  callEnd(
    @ConnectedSocket() socket: AuthenticatedSocket,
    @MessageBody() payload: { receiverId: string; callId: string },
  ) {
    const sender = this.requireUser(socket);
    this.server.to(this.userRoom(payload.receiverId)).emit("call:end", {
      callId: payload.callId,
      senderId: sender.id,
    });
  }

  @SubscribeMessage("webrtc:offer")
  forwardOffer(
    @ConnectedSocket() socket: AuthenticatedSocket,
    @MessageBody() payload: CallPayload,
  ) {
    this.forwardWebRtc(socket, "webrtc:offer", payload);
  }

  @SubscribeMessage("webrtc:answer")
  forwardAnswer(
    @ConnectedSocket() socket: AuthenticatedSocket,
    @MessageBody() payload: CallPayload,
  ) {
    this.forwardWebRtc(socket, "webrtc:answer", payload);
  }

  @SubscribeMessage("webrtc:ice-candidate")
  forwardIceCandidate(
    @ConnectedSocket() socket: AuthenticatedSocket,
    @MessageBody() payload: CallPayload,
  ) {
    this.forwardWebRtc(socket, "webrtc:ice-candidate", payload);
  }

  private forwardWebRtc(
    socket: AuthenticatedSocket,
    event: string,
    payload: CallPayload,
  ) {
    const sender = this.requireUser(socket);
    this.server.to(this.userRoom(payload.receiverId)).emit(event, {
      ...payload,
      senderId: sender.id,
    });
  }

  private extractToken(socket: Socket) {
    const authToken = socket.handshake.auth?.token;
    const header = socket.handshake.headers.authorization;
    const bearer = Array.isArray(header) ? header[0] : header;
    const headerToken = bearer?.startsWith("Bearer ")
      ? bearer.slice("Bearer ".length)
      : null;
    const token = authToken || headerToken;

    if (!token || typeof token !== "string") {
      throw new Error("Missing socket token");
    }

    return token;
  }

  private requireUser(socket: AuthenticatedSocket) {
    if (!socket.data.user) {
      throw new Error("Socket is not authenticated");
    }

    return socket.data.user;
  }

  private userRoom(userId: string) {
    return `user:${userId}`;
  }

  private chatRoom(chatId: string) {
    return `chat:${chatId}`;
  }

  private toError(error: unknown) {
    return {
      ok: false,
      message: error instanceof Error ? error.message : "Unknown socket error",
    };
  }
}
