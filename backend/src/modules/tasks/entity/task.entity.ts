export class TaskEntity {
  id!: string;
  userId!: string;
  title!: string;
  dueAt?: string | null;
  tags!: string[];
  status!: 'backlog' | 'inProgress' | 'done' | 'missed' | 'deleted';
  difficulty!: 'easy' | 'medium' | 'hard';
  priority!: 'low' | 'medium' | 'high';
  mappedSkills!: string[];
  isDailyTask!: boolean;
  isRequiredDailyTask!: boolean;
  dailyDateKey?: string | null;
  completedAt?: string | null;
  deletedAt?: string | null;
  clientUpdatedAt!: string;
  createdAt!: string;
  updatedAt!: string;
}
