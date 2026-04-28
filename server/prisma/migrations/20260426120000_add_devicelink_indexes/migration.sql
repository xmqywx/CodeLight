-- Add single-column indexes on DeviceLink so the OR-on-source-or-target
-- lookup in getAccessibleDeviceIds + canAccessSession + notifyLinkedIPhones
-- can use an index. The composite @@unique([sourceDeviceId, targetDeviceId])
-- can serve a leading-prefix lookup on sourceDeviceId, but cannot help when
-- the query filters on targetDeviceId alone, so the OR was forcing a full
-- table scan on every socket message.
CREATE INDEX IF NOT EXISTS "DeviceLink_sourceDeviceId_idx" ON "DeviceLink"("sourceDeviceId");
CREATE INDEX IF NOT EXISTS "DeviceLink_targetDeviceId_idx" ON "DeviceLink"("targetDeviceId");
