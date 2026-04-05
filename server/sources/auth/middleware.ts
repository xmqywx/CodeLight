import { FastifyRequest, FastifyReply } from 'fastify';
import { verifyToken } from './crypto';
import { config } from '@/config';

declare module 'fastify' {
    interface FastifyRequest {
        deviceId?: string;
    }
}

export function extractToken(header: string | undefined): string | null {
    if (!header || !header.startsWith('Bearer ')) return null;
    return header.slice(7) || null;
}

export async function authMiddleware(
    request: FastifyRequest,
    reply: FastifyReply
): Promise<void> {
    const token = extractToken(request.headers.authorization);
    if (!token) {
        reply.code(401).send({ error: 'Missing authorization token' });
        return;
    }

    const payload = verifyToken(token, config.masterSecret);
    if (!payload) {
        reply.code(401).send({ error: 'Invalid token' });
        return;
    }

    request.deviceId = payload.deviceId;
}
