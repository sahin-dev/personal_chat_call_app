import { MessageType } from "@prisma/client";
import {
  IsEnum,
  IsMongoId,
  IsOptional,
  IsString,
  ValidateIf,
} from "class-validator";

export class CreateMessageDto {
  @IsEnum(MessageType)
  type: MessageType;

  @IsOptional()
  @IsString()
  text?: string;

  @ValidateIf((dto: CreateMessageDto) => dto.type === MessageType.FILE)
  @IsMongoId()
  fileId?: string;

  @IsOptional()
  @IsString()
  clientId?: string;
}
