import { Inject, Injectable, UnauthorizedException } from '@nestjs/common';
import { createClerkClient } from '@clerk/backend';
import type { FastifyRequest } from 'fastify';
import { DevicePlatform } from '@prisma/client';
import type { Env } from '@/common/config/env';
import { AuthenticatedUser } from '@/common/types/authenticated-user.type';
import { UsersService } from '@/modules/users/service/users.service';
import { DevicesService } from '@/modules/devices/service/devices.service';

@Injectable()
export class AuthService {
  private readonly clerkClient;

  constructor(
    @Inject('ENV') private readonly env: Env,
    private readonly usersService: UsersService,
    private readonly devicesService: DevicesService,
  ) {
    this.clerkClient = createClerkClient({
      secretKey: env.CLERK_SECRET_KEY,
      publishableKey: env.CLERK_PUBLISHABLE_KEY,
    });
  }

  async authenticate(request: FastifyRequest): Promise<AuthenticatedUser> {
    if (this.env.AUTH_MODE === 'dev') {
      return this.authenticateDev(request);
    }

    return this.authenticateClerk(request);
  }

  private async authenticateDev(request: FastifyRequest): Promise<AuthenticatedUser> {
    const rawUserId = this.header(request, 'x-user-id') ?? '00000000-0000-0000-0000-000000000001';
    const rawDeviceId = this.header(request, 'x-device-id') ?? 'dev-device';
    const email = this.header(request, 'x-user-email') ?? 'dev@example.com';

    const userId = this.ensureUuidOrFallback(rawUserId, '00000000-0000-0000-0000-000000000001');
    const user = await this.usersService.ensureDevUser(userId, email);

    const device = await this.devicesService.register({
      userId: user.id,
      clientDeviceId: rawDeviceId,
      platform: DevicePlatform.UNKNOWN,
      appVersion: this.header(request, 'x-app-version') ?? undefined,
    });

    return {
      id: user.id,
      email: user.email ?? undefined,
      clientDeviceId: rawDeviceId,
      serverDeviceId: device.id,
      deviceId: device.id,
    };
  }

  private async authenticateClerk(request: FastifyRequest): Promise<AuthenticatedUser> {
    const token = this.bearerToken(request);
    if (token == null) {
      throw new UnauthorizedException('Missing bearer token');
    }

    const verifyTokenFn: ((token: string, options?: Record<string, unknown>) => Promise<any>) | undefined =
      (this.clerkClient as any).verifyToken;

    if (typeof verifyTokenFn !== 'function') {
      throw new UnauthorizedException('Clerk token verifier not available');
    }

    const payload = await verifyTokenFn.call(this.clerkClient, token, {
      jwtKey: undefined,
      authorizedParties: undefined,
      issuer: this.env.CLERK_ISSUER,
    });

    const clerkUserId = payload?.sub as string | undefined;
    if (!clerkUserId) {
      throw new UnauthorizedException('Invalid token payload');
    }

    const email = (payload?.email as string | undefined) ?? undefined;
    const user = await this.usersService.ensureClerkUser(clerkUserId, email);

    const rawDeviceId = this.header(request, 'x-device-id');
    let deviceId: string | undefined;

    if (rawDeviceId) {
      const platformHeader = this.header(request, 'x-device-platform');
      const platform = platformHeader === 'IOS' || platformHeader === 'MACOS' ? platformHeader : 'UNKNOWN';
      const device = await this.devicesService.register({
        userId: user.id,
        clientDeviceId: rawDeviceId,
        platform: platform as DevicePlatform,
        appVersion: this.header(request, 'x-app-version') ?? undefined,
      });
      deviceId = device.id;
    }

    return {
      id: user.id,
      clerkUserId,
      email: user.email ?? undefined,
      clientDeviceId: rawDeviceId,
      serverDeviceId: deviceId,
      deviceId,
    };
  }

  private bearerToken(request: FastifyRequest): string | undefined {
    const value = this.header(request, 'authorization');
    if (!value) return undefined;
    const [scheme, token] = value.split(' ');
    if (!scheme || !token) return undefined;
    if (scheme.toLowerCase() !== 'bearer') return undefined;
    return token;
  }

  private header(request: FastifyRequest, key: string): string | undefined {
    const value = request.headers[key];
    if (typeof value === 'string') return value;
    if (Array.isArray(value) && typeof value[0] === 'string') return value[0];
    return undefined;
  }

  private ensureUuidOrFallback(value: string, fallback: string): string {
    const regex = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
    return regex.test(value) ? value : fallback;
  }
}
