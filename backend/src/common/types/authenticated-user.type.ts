export type AuthenticatedUser = {
  id: string;
  clerkUserId?: string;
  email?: string;
  clientDeviceId?: string;
  serverDeviceId?: string;
  // Deprecated alias for serverDeviceId.
  deviceId?: string;
};
