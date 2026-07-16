import {
  BadRequestException,
  Injectable,
  NotFoundException,
} from "@nestjs/common";
import { ChatType, ReceiptStatus } from "@prisma/client";
import { PrismaService } from "../prisma/prisma.service";

@Injectable()
export class ChatsService {
  constructor(private readonly prisma: PrismaService) {}

  async createDirectChat(currentUserId: string, otherUserId: string) {
    if (currentUserId === otherUserId) {
      throw new BadRequestException("Cannot create a chat with yourself");
    }

    const otherUser = await this.prisma.user.findUnique({
      where: { id: otherUserId },
      select: { id: true },
    });

    if (!otherUser) {
      throw new NotFoundException("User not found");
    }

    const existingChat = await this.prisma.chat.findFirst({
      where: {
        type: ChatType.DIRECT,
        participantIds: { hasEvery: [currentUserId, otherUserId] },
      },
    });

    if (existingChat) {
      return this.getChatForUser(existingChat.id, currentUserId);
    }

    const chat = await this.prisma.chat.create({
      data: {
        type: ChatType.DIRECT,
        participantIds: [currentUserId, otherUserId],
      },
    });

    return this.getChatForUser(chat.id, currentUserId);
  }

  async listChats(userId: string) {
    const chats = await this.prisma.chat.findMany({
      where: { participantIds: { has: userId } },
      orderBy: { updatedAt: "desc" },
    });

    return Promise.all(chats.map((chat) => this.decorateChat(chat, userId)));
  }

  async getChatForUser(chatId: string, userId: string) {
    const chat = await this.prisma.chat.findFirst({
      where: { id: chatId, participantIds: { has: userId } },
    });

    if (!chat) {
      throw new NotFoundException("Chat not found");
    }

    return this.decorateChat(chat, userId);
  }

  async assertParticipant(chatId: string, userId: string) {
    const chat = await this.prisma.chat.findFirst({
      where: { id: chatId, participantIds: { has: userId } },
    });

    if (!chat) {
      throw new NotFoundException("Chat not found");
    }

    return chat;
  }

  private async decorateChat(
    chat: {
      id: string;
      type: ChatType;
      participantIds: string[];
      lastMessageId: string | null;
      createdAt: Date;
      updatedAt: Date;
    },
    userId: string,
  ) {
    const [participants, lastMessage, unreadCount] = await Promise.all([
      this.prisma.user.findMany({
        where: { id: { in: chat.participantIds } },
        select: { id: true, name: true, email: true, avatarUrl: true },
      }),
      chat.lastMessageId
        ? this.prisma.message.findUnique({
            where: { id: chat.lastMessageId },
            include: { file: true, receipts: true },
          })
        : null,
      this.prisma.messageReceipt.count({
        where: {
          userId,
          status: { not: ReceiptStatus.READ },
          message: { chatId: chat.id },
        },
      }),
    ]);

    return {
      ...chat,
      participants,
      lastMessage,
      unreadCount,
    };
  }
}
