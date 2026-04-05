import { describe, it, expect } from 'vitest';
import { extractToken } from './middleware';

describe('extractToken', () => {
    it('should extract Bearer token from header', () => {
        const token = extractToken('Bearer abc123');
        expect(token).toBe('abc123');
    });

    it('should return null for missing header', () => {
        expect(extractToken(undefined)).toBeNull();
        expect(extractToken('')).toBeNull();
    });

    it('should return null for non-Bearer auth', () => {
        expect(extractToken('Basic abc123')).toBeNull();
    });
});
