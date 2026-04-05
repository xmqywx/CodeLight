import type { Socket } from 'socket.io';
import { db } from '@/storage/db';
import { allocateSessionSeq } from '@/storage/seq';
import type { EventRouter } from './eventRouter';
import { sendPushToDevice } from '@/push/apns';

export function registerSessionHandler(
    socket: Socket,
    deviceId: string,
    eventRouter: EventRouter
) {
    socket.on('message', async (data: {
        sid: string;
        message: string;
        localId?: string;
    }, callback?: (result: any) => void) => {
        try {
            const session = await db.session.findFirst({
                where: { id: data.sid },
            });
            if (!session) {
                console.log(`[sessionHandler] Session not found: ${data.sid}`);
                callback?.({ error: 'Session not found' });
                return;
            }

            if (data.localId) {
                const existing = await db.sessionMessage.findUnique({
                    where: { sessionId_localId: { sessionId: data.sid, localId: data.localId } },
                });
                if (existing) {
                    callback?.({ id: existing.id, seq: existing.seq });
                    return;
                }
            }

            const seq = await allocateSessionSeq(data.sid);
            const message = await db.sessionMessage.create({
                data: {
                    sessionId: data.sid,
                    content: data.message,
                    localId: data.localId,
                    seq,
                },
            });

            eventRouter.emitUpdate(deviceId, 'update', {
                type: 'new-message',
                sessionId: data.sid,
                message: { id: message.id, seq, content: data.message, localId: data.localId },
            }, { type: 'all-interested-in-session', sessionId: data.sid }, socket);

            // Send push notification for important events
            try {
                const parsed = JSON.parse(data.message);
                if (parsed.type === 'tool' && parsed.toolStatus === 'error') {
                    // Push all devices about errors
                    const devices = await db.device.findMany({ select: { id: true } });
                    for (const d of devices) {
                        sendPushToDevice(d.id, { title: 'Tool Error', body: `${parsed.toolName || 'Tool'} failed` }, db);
                    }
                }
            } catch {}

            callback?.({ id: message.id, seq });
        } catch (error) {
            callback?.({ error: 'Failed to save message' });
        }
    });

    socket.on('update-metadata', async (data: {
        sid: string;
        metadata: string;
        expectedVersion: number;
    }, callback?: (result: any) => void) => {
        const result = await db.session.updateMany({
            where: {
                id: data.sid,
                metadataVersion: data.expectedVersion,
            },
            data: {
                metadata: data.metadata,
                metadataVersion: data.expectedVersion + 1,
            },
        });

        if (result.count === 0) {
            callback?.({ result: 'conflict' });
            return;
        }

        eventRouter.emitUpdate(deviceId, 'update', {
            type: 'update-session',
            sessionId: data.sid,
            metadata: data.metadata,
        }, { type: 'all-interested-in-session', sessionId: data.sid }, socket);

        callback?.({ result: 'ok', version: data.expectedVersion + 1 });
    });

    socket.on('session-alive', async (data: { sid: string }) => {
        await db.session.update({
            where: { id: data.sid },
            data: { lastActiveAt: new Date(), active: true },
        }).catch(() => {});

        eventRouter.emitEphemeral(deviceId, 'ephemeral', {
            type: 'activity',
            sessionId: data.sid,
            active: true,
        });
    });

    socket.on('session-end', async (data: { sid: string }) => {
        await db.session.update({
            where: { id: data.sid },
            data: { active: false, lastActiveAt: new Date() },
        }).catch(() => {});

        eventRouter.emitUpdate(deviceId, 'update', {
            type: 'update-session',
            sessionId: data.sid,
            active: false,
        }, { type: 'all-interested-in-session', sessionId: data.sid });
    });
}
