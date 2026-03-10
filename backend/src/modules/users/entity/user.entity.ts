export class UserEntity {
  id!: string;
  clerkUserId?: string | null;
  email?: string | null;
  createdAt!: Date;
  updatedAt!: Date;
}
