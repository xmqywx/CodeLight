import { db } from '@/storage/db';

/**
 * Get all device IDs that a device has access to (itself + linked devices).
 * Used for ownership checks — a device can access its own sessions
 * AND sessions belonging to devices it has been paired with.
 */
export async function getAccessibleDeviceIds(deviceId: string): Promise<string[]> {
    const links = await db.deviceLink.findMany({
        where: {
            OR: [
                { sourceDeviceId: deviceId },
                { targetDeviceId: deviceId },
            ],
        },
        select: {
            sourceDeviceId: true,
            targetDeviceId: true,
        },
    });

    const ids = new Set<string>([deviceId]);
    for (const link of links) {
        ids.add(link.sourceDeviceId);
        ids.add(link.targetDeviceId);
    }

    return Array.from(ids);
}

/**
 * Check if a device can access a specific session.
 */
export async function canAccessSession(deviceId: string, sessionId: string): Promise<boolean> {
    const session = await db.session.findUnique({
        where: { id: sessionId },
        select: { deviceId: true },
    });
    if (!session) return false;
    if (session.deviceId === deviceId) return true;

    // Check if devices are linked
    const linked = await db.deviceLink.findFirst({
        where: {
            OR: [
                { sourceDeviceId: deviceId, targetDeviceId: session.deviceId },
                { sourceDeviceId: session.deviceId, targetDeviceId: deviceId },
            ],
        },
    });

    return linked !== null;
}

/**
 * Link two devices together (bidirectional).
 */
export async function linkDevices(deviceId1: string, deviceId2: string): Promise<void> {
    await db.deviceLink.upsert({
        where: {
            sourceDeviceId_targetDeviceId: {
                sourceDeviceId: deviceId1,
                targetDeviceId: deviceId2,
            },
        },
        create: {
            sourceDeviceId: deviceId1,
            targetDeviceId: deviceId2,
        },
        update: {},
    });
}
