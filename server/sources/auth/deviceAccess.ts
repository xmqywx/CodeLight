import { db } from '@/storage/db';

// Hot-path cache for canAccessSession. Every socket message hits it (phase
// events, tool events, content). Without caching that's 2 DB queries per
// message — for an active Claude session that's 50-100 wasted roundtrips
// per minute. Pairings change rarely; a 30s TTL is safe.
type CacheEntry = { allowed: boolean; expiresAt: number };
const accessCache = new Map<string, CacheEntry>();
const ACCESS_CACHE_TTL_MS = 30_000;

function accessKey(deviceId: string, sessionId: string): string {
    return `${deviceId}:${sessionId}`;
}

/** Drop cached access decisions. Call when pairings change or sessions are deleted. */
export function invalidateAccessCache(): void {
    accessCache.clear();
}

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
 * Cached for 30s — see accessCache notes above.
 */
export async function canAccessSession(deviceId: string, sessionId: string): Promise<boolean> {
    const key = accessKey(deviceId, sessionId);
    const now = Date.now();
    const cached = accessCache.get(key);
    if (cached && cached.expiresAt > now) {
        return cached.allowed;
    }

    const session = await db.session.findUnique({
        where: { id: sessionId },
        select: { deviceId: true },
    });
    if (!session) {
        // Don't cache "session not found" — it might be created in a moment.
        return false;
    }
    let allowed = session.deviceId === deviceId;
    if (!allowed) {
        const linked = await db.deviceLink.findFirst({
            where: {
                OR: [
                    { sourceDeviceId: deviceId, targetDeviceId: session.deviceId },
                    { sourceDeviceId: session.deviceId, targetDeviceId: deviceId },
                ],
            },
            select: { id: true },
        });
        allowed = linked !== null;
    }
    accessCache.set(key, { allowed, expiresAt: now + ACCESS_CACHE_TTL_MS });
    return allowed;
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
    // Drop cached access decisions so newly-paired devices see access right away.
    invalidateAccessCache();
}
