import { describe, it, expect } from 'vitest';
import nacl from 'tweetnacl';
import { encodeBase64 } from 'tweetnacl-util';
import { verifySignature, createToken, verifyToken } from './crypto';

describe('verifySignature', () => {
    it('should verify a valid Ed25519 signature', () => {
        const keyPair = nacl.sign.keyPair();
        const message = new TextEncoder().encode('hello');
        const signature = nacl.sign.detached(message, keyPair.secretKey);
        const valid = verifySignature(
            encodeBase64(message),
            encodeBase64(signature),
            encodeBase64(keyPair.publicKey)
        );
        expect(valid).toBe(true);
    });

    it('should reject an invalid signature', () => {
        const keyPair = nacl.sign.keyPair();
        const message = new TextEncoder().encode('hello');
        const badSig = new Uint8Array(64);
        const valid = verifySignature(
            encodeBase64(message),
            encodeBase64(badSig),
            encodeBase64(keyPair.publicKey)
        );
        expect(valid).toBe(false);
    });
});

describe('createToken / verifyToken', () => {
    it('should create and verify a token', () => {
        const token = createToken('device-123', 'test-secret');
        const payload = verifyToken(token, 'test-secret');
        expect(payload).not.toBeNull();
        expect(payload!.deviceId).toBe('device-123');
    });

    it('should reject a token with wrong secret', () => {
        const token = createToken('device-123', 'test-secret');
        const payload = verifyToken(token, 'wrong-secret');
        expect(payload).toBeNull();
    });
});
