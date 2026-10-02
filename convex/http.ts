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
http.route({
  path: "/v1/snapshot",
  method: "GET",
  handler: httpActionGeneric(async (ctx, request) => {
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
    if (!equalHash(actual, configured))
      return json({ error: "unauthorized" }, 401);
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
export default http;
