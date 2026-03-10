import { randomUUID } from 'crypto';
import { AsyncLocalStorage } from 'async_hooks';

export type RequestContextData = {
  requestId: string;
};

const storage = new AsyncLocalStorage<RequestContextData>();

export function withRequestContext<T>(requestId: string, run: () => T): T {
  return storage.run({ requestId }, run);
}

export function getRequestContext(): RequestContextData {
  return storage.getStore() ?? { requestId: randomUUID() };
}
