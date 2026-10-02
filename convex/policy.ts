export const MAX_ENVELOPE_BYTES = 750_000;
export function validateEnvelope(
  envelope: string,
  digest: string,
  capturedAt: string,
): void {
  if (new TextEncoder().encode(envelope).length > MAX_ENVELOPE_BYTES)
    throw new Error("snapshot_too_large");
  if (!/^[a-f0-9]{64}$/.test(digest)) throw new Error("invalid_digest");
  if (
    !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/.test(capturedAt) ||
    !Number.isFinite(Date.parse(capturedAt)) ||
    new Date(capturedAt).toISOString() !== capturedAt
  )
    throw new Error("invalid_timestamp");
  const parsed = JSON.parse(envelope);
  if (
    parsed.version !== 1 ||
    parsed.algorithm !== "AES-256-GCM" ||
    typeof parsed.combined !== "string" ||
    !/^[A-Za-z0-9+/]+={0,2}$/.test(parsed.combined) ||
    parsed.combined.length < 40
  )
    throw new Error("invalid_envelope");
}
export function equalHash(a: string, b: string): boolean {
  if (a.length !== 64 || b.length !== 64) return false;
  let difference = 0;
  for (let i = 0; i < 64; i++) difference |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return difference === 0;
}
export function nextRevision(
  latest: { revision: number; capturedAt: string } | null,
  expected: number,
  capturedAt: string,
): number {
  if (!Number.isSafeInteger(expected) || expected < 0)
    throw new Error("invalid_revision");
  if ((latest?.revision ?? 0) !== expected)
    throw new Error("revision_conflict");
  if (latest && capturedAt < latest.capturedAt)
    throw new Error("stale_snapshot");
  return expected + 1;
}
