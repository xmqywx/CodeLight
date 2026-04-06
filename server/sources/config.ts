export const config = {
    port: parseInt(process.env.PORT || '3005', 10),
    masterSecret: process.env.MASTER_SECRET || '',
    databaseUrl: process.env.DATABASE_URL || '',
    tokenExpiryDays: parseInt(process.env.TOKEN_EXPIRY_DAYS || '30', 10),
} as const;
