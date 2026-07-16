import { Body, Controller, Get, Param, Post, UseGuards } from "@nestjs/common";
import { CurrentUser } from "../../common/decorators/current-user.decorator";
import { JwtAuthGuard } from "../../common/guards/jwt-auth.guard";
import { AuthenticatedUser } from "../../common/types/authenticated-request";
import { ChatsService } from "./chats.service";
import { CreateDirectChatDto } from "./dto/create-direct-chat.dto";

@Controller("chats")
@UseGuards(JwtAuthGuard)
export class ChatsController {
  constructor(private readonly chatsService: ChatsService) {}

  @Post("direct")
  createDirectChat(
    @CurrentUser() user: AuthenticatedUser,
    @Body() dto: CreateDirectChatDto,
  ) {
    return this.chatsService.createDirectChat(user.id, dto.userId);
  }

  @Get()
  listChats(@CurrentUser() user: AuthenticatedUser) {
    return this.chatsService.listChats(user.id);
  }

  @Get(":id")
  getChat(@Param("id") id: string, @CurrentUser() user: AuthenticatedUser) {
    return this.chatsService.getChatForUser(id, user.id);
  }
}
