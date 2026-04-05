import nacl from 'tweetnacl';
import { decodeBase64 } from 'tweetnacl-util';
import jwt from 'jsonwebtoken';

export function verifySignature(
    messageBase64: string,
    signatureBase64: string,
    publicKeyBase64: string
): boolean {
    try {
        const message = decodeBase64(messageBase64);
        const signature = decodeBase64(signatureBase64);
        const publicKey = decodeBase64(publicKeyBase64);
        return nacl.sign.detached.verify(message, signature, publicKey);
    } catch {
        return false;
    }
}

export interface TokenPayload {
    deviceId: string;
    iat?: number;
}

export function createToken(deviceId: string, secret: string): string {
    return jwt.sign({ deviceId }, secret);
}

export function verifyToken(token: string, secret: string): TokenPayload | null {
    try {
        return jwt.verify(token, secret) as TokenPayload;
    } catch {
        return null;
    }
}
