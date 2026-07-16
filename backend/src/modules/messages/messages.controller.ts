import {
  Body,
  Controller,
  Delete,
  Get,
  Param,
  Post,
  Query,
  UseGuards,
} from "@nestjs/common";
import { CurrentUser } from "../../common/decorators/current-user.decorator";
import { JwtAuthGuard } from "../../common/guards/jwt-auth.guard";
import { AuthenticatedUser } from "../../common/types/authenticated-request";
import { CreateMessageDto } from "./dto/create-message.dto";
import { MessagesService } from "./messages.service";

@Controller()
@UseGuards(JwtAuthGuard)
export class MessagesController {
  constructor(private readonly messagesService: MessagesService) {}

  @Get("chats/:chatId/messages")
  listMessages(
    @Param("chatId") chatId: string,
    @CurrentUser() user: AuthenticatedUser,
    @Query("take") take?: string,
    @Query("cursor") cursor?: string,
  ) {
    const parsedTake = take ? Number.parseInt(take, 10) : undefined;
    return this.messagesService.listMessages(
      chatId,
      user.id,
      parsedTake,
      cursor,
    );
  }

  @Post("chats/:chatId/messages")
  createMessage(
    @Param("chatId") chatId: string,
    @CurrentUser() user: AuthenticatedUser,
    @Body() dto: CreateMessageDto,
  ) {
    return this.messagesService.createMessage(chatId, user.id, dto);
  }

  @Delete("messages/:messageId")
  deleteMessage(
    @Param("messageId") messageId: string,
    @CurrentUser() user: AuthenticatedUser,
  ) {
    return this.messagesService.deleteMessage(messageId, user.id);
  }

  @Post("messages/:messageId/read")
  markRead(
    @Param("messageId") messageId: string,
    @CurrentUser() user: AuthenticatedUser,
  ) {
    return this.messagesService.markRead(messageId, user.id);
  }

  @Post("chats/:chatId/read")
  markChatRead(
    @Param("chatId") chatId: string,
    @CurrentUser() user: AuthenticatedUser,
  ) {
    return this.messagesService.markChatRead(chatId, user.id);
  }
}
