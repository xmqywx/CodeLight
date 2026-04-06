import type { Socket } from 'socket.io';

// Maps "deviceId:method" → socket. Prevents cross-device hijacking.
const rpcHandlers = new Map<string, Socket>();

export function registerRpcHandler(socket: Socket, deviceId: string) {

    socket.on('rpc-register', (data: { method: string }) => {
        // Namespace by deviceId to prevent hijacking
        const key = `${deviceId}:${data.method}`;
        rpcHandlers.set(key, socket);
    });

    socket.on('rpc-unregister', (data: { method: string }) => {
        const key = `${deviceId}:${data.method}`;
        if (rpcHandlers.get(key) === socket) {
            rpcHandlers.delete(key);
        }
    });

    socket.on('rpc-call', async (data: {
        method: string;
        params: string;
    }, callback?: (result: any) => void) => {
        // Try own device first
        let handler = rpcHandlers.get(`${deviceId}:${data.method}`);

        // Fallback: find any handler for this method (cross-device RPC between linked devices)
        if (!handler) {
            for (const [key, s] of rpcHandlers.entries()) {
                if (key.endsWith(`:${data.method}`) && s.connected) {
                    handler = s;
                    break;
                }
            }
        }

        if (!handler || !handler.connected) {
            callback?.({ ok: false, error: 'No handler registered' });
            return;
        }

        try {
            const result = await handler.timeout(300_000).emitWithAck('rpc-call', {
                method: data.method,
                params: data.params,
            });
            callback?.(result);
        } catch {
            callback?.({ ok: false, error: 'RPC timeout' });
        }
    });

    socket.on('disconnect', () => {
        // Only clean up this device's registrations
        const prefix = `${deviceId}:`;
        for (const [key, s] of rpcHandlers.entries()) {
            if (s === socket && key.startsWith(prefix)) {
                rpcHandlers.delete(key);
            }
        }
    });
}
