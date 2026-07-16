import { IsMongoId } from "class-validator";

export class CreateDirectChatDto {
  @IsMongoId()
  userId: string;
}
