export class FocusSessionEntity {
  id!: string;
  userId!: string;
  startAt!: string;
  endAt!: string;
  durationMinutes!: number;
  mode!: 'POMODORO' | 'CUSTOM';
  clientUpdatedAt!: string;
  createdAt!: string;
  updatedAt!: string;
}
