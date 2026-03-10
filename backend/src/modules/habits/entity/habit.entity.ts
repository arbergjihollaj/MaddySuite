export class HabitEntity {
  id!: string;
  userId!: string;
  title!: string;
  symbol!: string;
  colorHex!: string;
  goalKind!: string;
  targetValue!: number;
  scheduleMode!: string;
  weekdays!: number[];
  everyXDays!: number;
  streak!: number;
  lastCompletedDateKey?: string | null;
  clientUpdatedAt!: string;
  createdAt!: string;
  updatedAt!: string;
}
