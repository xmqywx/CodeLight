import { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { verifySignature, createToken } from './crypto';
import { db } from '@/storage/db';
import { config } from '@/config';

export async function authRoutes(app: FastifyInstance) {
    app.post('/v1/auth', {
        schema: {
            body: z.object({
                publicKey: z.string(),
                challenge: z.string(),
                signature: z.string(),
            }),
        },
    }, async (request, reply) => {
        const { publicKey, challenge, signature } = request.body as {
            publicKey: string;
            challenge: string;
            signature: string;
        };

        if (!verifySignature(challenge, signature, publicKey)) {
            return reply.code(401).send({ error: 'Invalid signature' });
        }

        const device = await db.device.upsert({
            where: { publicKey },
            create: { publicKey, name: 'Unknown Device' },
            update: {},
        });

        const token = createToken(device.id, config.masterSecret, config.tokenExpiryDays);
        return { success: true, token, deviceId: device.id };
    });
}
