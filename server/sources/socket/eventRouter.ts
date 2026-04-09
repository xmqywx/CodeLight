import type { Socket } from 'socket.io';

export interface ClientConnection {
    connectionType: 'session-scoped' | 'user-scoped';
    socket: Socket;
    deviceId: string;
    sessionId?: string;
}

export type RecipientFilter =
    | { type: 'all-interested-in-session'; sessionId: string }
    | { type: 'user-scoped-only' }
    | { type: 'all' };

export class EventRouter {
    private connections = new Map<string, Set<ClientConnection>>();

    addConnection(deviceId: string, connection: ClientConnection) {
        if (!this.connections.has(deviceId)) {
            this.connections.set(deviceId, new Set());
        }
        this.connections.get(deviceId)!.add(connection);
    }

    removeConnection(deviceId: string, connection: ClientConnection) {
        const conns = this.connections.get(deviceId);
        if (conns) {
            conns.delete(connection);
            if (conns.size === 0) this.connections.delete(deviceId);
        }
    }

    getConnections(deviceId: string): ClientConnection[] {
        return Array.from(this.connections.get(deviceId) || []);
    }

    /** Broadcast to ALL devices' connections matching the filter */
    emitUpdate(
        _deviceId: string,
        event: string,
        payload: unknown,
        filter: RecipientFilter,
        skipSocket?: Socket
    ) {
        let sent = 0;
        let skipped = 0;
        for (const [devId, conns] of this.connections.entries()) {
            for (const conn of conns) {
                if (conn.socket === skipSocket) { skipped++; continue; }
                if (this.shouldSend(conn, filter)) {
                    conn.socket.emit(event, payload);
                    sent++;
                } else {
                    skipped++;
                }
            }
        }
        const type = (payload as any)?.type || event;
        const deviceList = Array.from(this.connections.entries()).map(([id, cs]) => `${id.substring(0,10)}(${cs.size})`).join(', ');
        console.log(`[EventRouter] ${type}: sent=${sent} skipped=${skipped} totalDevices=${this.connections.size} devices=[${deviceList}]`);
    }

    emitEphemeral(_deviceId: string, event: string, payload: unknown) {
        this.emitUpdate(_deviceId, event, payload, { type: 'all' });
    }

    /** Emit an event to all connections of a specific target device. */
    emitToDevice(targetDeviceId: string, event: string, payload: unknown): number {
        const conns = this.connections.get(targetDeviceId);
        if (!conns) return 0;
        let count = 0;
        for (const conn of conns) {
            conn.socket.emit(event, payload);
            count++;
        }
        return count;
    }

    private shouldSend(conn: ClientConnection, filter: RecipientFilter): boolean {
        switch (filter.type) {
            case 'all':
                return true;
            case 'user-scoped-only':
                return conn.connectionType === 'user-scoped';
            case 'all-interested-in-session':
                return conn.connectionType === 'user-scoped' ||
                    (conn.connectionType === 'session-scoped' && conn.sessionId === filter.sessionId);
        }
    }
}
