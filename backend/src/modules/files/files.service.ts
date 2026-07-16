import { Injectable, NotFoundException } from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import { PrismaService } from "../prisma/prisma.service";

@Injectable()
export class FilesService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly config: ConfigService,
  ) {}

  async createFileRecord(file: Express.Multer.File, uploaderId: string) {
    const uploadDir = this.config.get<string>("UPLOAD_DIR", "uploads");
    const publicBaseUrl = this.config.get<string>(
      "PUBLIC_BASE_URL",
      "http://localhost:3000",
    );
    const storageKey = file.filename;

    return this.prisma.file.create({
      data: {
        uploaderId,
        originalName: file.originalname,
        mimeType: file.mimetype,
        size: file.size,
        storageKey,
        url: `${publicBaseUrl}/${uploadDir}/${storageKey}`,
      },
    });
  }

  async getFile(id: string) {
    const file = await this.prisma.file.findUnique({ where: { id } });
    if (!file) {
      throw new NotFoundException("File not found");
    }

    return file;
  }
}
