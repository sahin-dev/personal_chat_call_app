import { Request } from "express";

export type AuthenticatedUser = {
  id: string;
  email: string;
  name: string;
};

export type AuthenticatedRequest = Request & {
  user: AuthenticatedUser;
};
