import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from "@nestjs/common";
import { MessageType, ReceiptStatus } from "@prisma/client";
import { ChatsService } from "../chats/chats.service";
import { PrismaService } from "../prisma/prisma.service";
import { CreateMessageDto } from "./dto/create-message.dto";

@Injectable()
export class MessagesService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly chatsService: ChatsService,
  ) {}

  async listMessages(
    chatId: string,
    userId: string,
    take = 50,
    cursor?: string,
  ) {
    await this.chatsService.assertParticipant(chatId, userId);

    const messages = await this.prisma.message.findMany({
      where: { chatId },
      include: { file: true, receipts: true },
      orderBy: { createdAt: "desc" },
      take: Math.min(take, 100),
      ...(cursor ? { skip: 1, cursor: { id: cursor } } : {}),
    });

    return messages.reverse();
  }

  async createMessage(chatId: string, senderId: string, dto: CreateMessageDto) {
    const chat = await this.chatsService.assertParticipant(chatId, senderId);

    if (dto.type === MessageType.TEXT && !dto.text?.trim()) {
      throw new BadRequestException("Text message cannot be empty");
    }

    if (dto.type === MessageType.FILE && !dto.fileId) {
      throw new BadRequestException("File message requires fileId");
    }

    if (dto.fileId) {
      const file = await this.prisma.file.findUnique({
        where: { id: dto.fileId },
      });
      if (!file) {
        throw new NotFoundException("File not found");
      }
    }

    const message = await this.prisma.message.create({
      data: {
        chatId,
        senderId,
        type: dto.type,
        text: dto.text?.trim() || null,
        fileId: dto.type === MessageType.FILE ? dto.fileId : null,
        receipts: {
          create: chat.participantIds.map((participantId) => ({
            userId: participantId,
            status:
              participantId === senderId
                ? ReceiptStatus.READ
                : ReceiptStatus.SENT,
          })),
        },
      },
      include: { file: true, receipts: true },
    });

    await this.prisma.chat.update({
      where: { id: chatId },
      data: { lastMessageId: message.id },
    });

    return message;
  }

  async deleteMessage(messageId: string, userId: string) {
    const message = await this.prisma.message.findUnique({
      where: { id: messageId },
    });

    if (!message) {
      throw new NotFoundException("Message not found");
    }

    if (message.senderId !== userId) {
      throw new ForbiddenException("You can only delete your own messages");
    }

    return this.prisma.message.update({
      where: { id: messageId },
      data: {
        text: null,
        fileId: null,
        deletedAt: new Date(),
      },
      include: { file: true, receipts: true },
    });
  }

  async markRead(messageId: string, userId: string) {
    const message = await this.prisma.message.findUnique({
      where: { id: messageId },
    });

    if (!message) {
      throw new NotFoundException("Message not found");
    }

    await this.chatsService.assertParticipant(message.chatId, userId);

    return this.prisma.messageReceipt.upsert({
      where: { messageId_userId: { messageId, userId } },
      update: { status: ReceiptStatus.READ },
      create: { messageId, userId, status: ReceiptStatus.READ },
    });
  }

  async markChatRead(chatId: string, userId: string) {
    await this.chatsService.assertParticipant(chatId, userId);
    const receipts = await this.prisma.messageReceipt.findMany({
      where: {
        userId,
        status: { not: ReceiptStatus.READ },
        message: { chatId, senderId: { not: userId } },
      },
      select: { messageId: true },
    });

    if (receipts.length === 0) return { count: 0, messageIds: [] };
    const messageIds = receipts.map((receipt) => receipt.messageId);
    const result = await this.prisma.messageReceipt.updateMany({
      where: {
        userId,
        messageId: { in: messageIds },
        status: { not: ReceiptStatus.READ },
      },
      data: { status: ReceiptStatus.READ },
    });
    return { count: result.count, messageIds };
  }

  async markDelivered(messageId: string, userId: string) {
    await this.prisma.messageReceipt.updateMany({
      where: { messageId, userId, status: ReceiptStatus.SENT },
      data: { status: ReceiptStatus.DELIVERED },
    });
  }

  async markPendingDelivered(userId: string) {
    const receipts = await this.prisma.messageReceipt.findMany({
      where: { userId, status: ReceiptStatus.SENT },
      select: {
        messageId: true,
        message: { select: { senderId: true } },
      },
    });
    if (receipts.length === 0) return [];

    await this.prisma.messageReceipt.updateMany({
      where: {
        userId,
        messageId: { in: receipts.map((receipt) => receipt.messageId) },
        status: ReceiptStatus.SENT,
      },
      data: { status: ReceiptStatus.DELIVERED },
    });
    return receipts;
  }

  async getMessage(messageId: string) {
    return this.prisma.message.findUniqueOrThrow({
      where: { id: messageId },
      include: { file: true, receipts: true },
    });
  }

  async getChatParticipantIds(chatId: string) {
    const chat = await this.prisma.chat.findUnique({
      where: { id: chatId },
      select: { participantIds: true },
    });

    return chat?.participantIds ?? [];
  }
}
