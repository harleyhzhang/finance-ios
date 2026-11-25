import {
  httpRouter,
  httpActionGeneric,
  makeFunctionReference,
} from "convex/server";
import { equalHash } from "./policy";
const http = httpRouter();
const headers = {
  "content-type": "application/json",
  "cache-control": "no-store",
  "x-content-type-options": "nosniff",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers });
http.route({
  path: "/health",
  method: "GET",
  handler: httpActionGeneric(async () =>
    json({ ok: true, service: "finance", version: 1 }),
  ),
});
async function deny(request: Request): Promise<Response | null> {
  // WORTH_READ_TOKEN_SHA256 is the pre-1.1 name, still honoured for existing deployments.
  const configured =
    process.env.FINANCE_READ_TOKEN_SHA256 ?? process.env.WORTH_READ_TOKEN_SHA256;
  if (!configured) return json({ error: "unavailable" }, 503);
  const authorization = request.headers.get("authorization") ?? "";
  if (!authorization.startsWith("Bearer ") || authorization.length > 512)
    return json({ error: "unauthorized" }, 401);
  const bytes = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(authorization.slice(7)),
  );
  const actual = Array.from(new Uint8Array(bytes), (b) =>
    b.toString(16).padStart(2, "0"),
  ).join("");
  return equalHash(actual, configured) ? null : json({ error: "unauthorized" }, 401);
}
http.route({
  path: "/v1/snapshot",
  method: "GET",
  handler: httpActionGeneric(async (ctx, request) => {
    const denied = await deny(request);
    if (denied) return denied;
    const record = await ctx.runQuery(
      makeFunctionReference<"query">("snapshots:latest"),
      {},
    );
    if (!record) return json({ error: "not_found" }, 404);
    const etag = '"' + record.digest + '"';
    if (request.headers.get("if-none-match") === etag)
      return new Response(null, { status: 304, headers: { ...headers, etag } });
    return new Response(
      JSON.stringify({
        revision: record.revision,
        capturedAt: record.capturedAt,
        digest: record.digest,
        envelope: JSON.parse(record.envelope),
      }),
      { headers: { ...headers, etag } },
    );
  }),
});
// Sealed month of history; immutable, so clients cache it by digest forever.
http.route({
  pathPrefix: "/v1/history/",
  method: "GET",
  handler: httpActionGeneric(async (ctx, request) => {
    const denied = await deny(request);
    if (denied) return denied;
    const digest = new URL(request.url).pathname.slice("/v1/history/".length);
    if (!/^[a-f0-9]{64}$/.test(digest)) return json({ error: "not_found" }, 404);
    const record = await ctx.runQuery(
      makeFunctionReference<"query">("history:chunk"),
      { digest },
    );
    if (!record) return json({ error: "not_found" }, 404);
    return new Response(
      JSON.stringify({ digest, envelope: JSON.parse(record.envelope) }),
      { headers: { ...headers, "cache-control": "private, max-age=31536000, immutable" } },
    );
  }),
});
export default http;
