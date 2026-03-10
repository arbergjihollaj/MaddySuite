import { Task, TaskDifficulty, TaskPriority, TaskStatus } from '@prisma/client';
import { TaskDifficultyDto, TaskPriorityDto, TaskStatusDto } from '../dto/task-enums.dto';
import { TaskEntity } from '../entity/task.entity';

export function dtoToStatus(status?: TaskStatusDto): TaskStatus {
  switch (status) {
    case TaskStatusDto.IN_PROGRESS:
      return TaskStatus.IN_PROGRESS;
    case TaskStatusDto.DONE:
      return TaskStatus.DONE;
    case TaskStatusDto.MISSED:
      return TaskStatus.MISSED;
    case TaskStatusDto.DELETED:
      return TaskStatus.DELETED;
    case TaskStatusDto.BACKLOG:
    default:
      return TaskStatus.BACKLOG;
  }
}

export function dtoToDifficulty(value?: TaskDifficultyDto): TaskDifficulty {
  switch (value) {
    case TaskDifficultyDto.EASY:
      return TaskDifficulty.EASY;
    case TaskDifficultyDto.HARD:
      return TaskDifficulty.HARD;
    case TaskDifficultyDto.MEDIUM:
    default:
      return TaskDifficulty.MEDIUM;
  }
}

export function dtoToPriority(value?: TaskPriorityDto): TaskPriority {
  switch (value) {
    case TaskPriorityDto.LOW:
      return TaskPriority.LOW;
    case TaskPriorityDto.HIGH:
      return TaskPriority.HIGH;
    case TaskPriorityDto.MEDIUM:
    default:
      return TaskPriority.MEDIUM;
  }
}

function statusToDto(status: TaskStatus): TaskStatusDto {
  switch (status) {
    case TaskStatus.IN_PROGRESS:
      return TaskStatusDto.IN_PROGRESS;
    case TaskStatus.DONE:
      return TaskStatusDto.DONE;
    case TaskStatus.MISSED:
      return TaskStatusDto.MISSED;
    case TaskStatus.DELETED:
      return TaskStatusDto.DELETED;
    case TaskStatus.BACKLOG:
    default:
      return TaskStatusDto.BACKLOG;
  }
}

function difficultyToDto(value: TaskDifficulty): TaskDifficultyDto {
  switch (value) {
    case TaskDifficulty.EASY:
      return TaskDifficultyDto.EASY;
    case TaskDifficulty.HARD:
      return TaskDifficultyDto.HARD;
    case TaskDifficulty.MEDIUM:
    default:
      return TaskDifficultyDto.MEDIUM;
  }
}

function priorityToDto(value: TaskPriority): TaskPriorityDto {
  switch (value) {
    case TaskPriority.LOW:
      return TaskPriorityDto.LOW;
    case TaskPriority.HIGH:
      return TaskPriorityDto.HIGH;
    case TaskPriority.MEDIUM:
    default:
      return TaskPriorityDto.MEDIUM;
  }
}

export function toTaskEntity(task: Task): TaskEntity {
  return {
    id: task.id,
    userId: task.userId,
    title: task.title,
    dueAt: task.dueAt?.toISOString() ?? null,
    tags: Array.isArray(task.tags) ? (task.tags as string[]) : [],
    status: statusToDto(task.status),
    difficulty: difficultyToDto(task.difficulty),
    priority: priorityToDto(task.priority),
    mappedSkills: Array.isArray(task.mappedSkills) ? (task.mappedSkills as string[]) : [],
    isDailyTask: task.isDailyTask,
    isRequiredDailyTask: task.isRequiredDailyTask,
    dailyDateKey: task.dailyDateKey,
    completedAt: task.completedAt?.toISOString() ?? null,
    deletedAt: task.deletedAt?.toISOString() ?? null,
    clientUpdatedAt: task.clientUpdatedAt.toISOString(),
    createdAt: task.createdAt.toISOString(),
    updatedAt: task.updatedAt.toISOString(),
  };
}
