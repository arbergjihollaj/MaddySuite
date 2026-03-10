export class ChangeEntity {
  cursor!: string;
  entityType!: string;
  entityId!: string;
  operation!: 'created' | 'updated' | 'deleted';
  occurredAt!: string;
  payload!: Record<string, unknown>;
}
