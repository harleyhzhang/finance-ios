import { internalMutationGeneric, internalQueryGeneric } from "convex/server";
import { v } from "convex/values";
import { validateChunk } from "./policy";
// Internal only. Chunks are immutable and content-addressed: an existing
// digest is skipped, so a publish stores only months that changed.
export const publishChunks = internalMutationGeneric({
  args: { chunks: v.array(v.object({ digest: v.string(), envelope: v.string() })) },
  handler: async (ctx, args) => {
    let stored = 0;
    for (const chunk of args.chunks) {
      validateChunk(chunk.envelope, chunk.digest);
      const existing = await ctx.db
        .query("historyChunks")
        .withIndex("by_digest", (q) => q.eq("digest", chunk.digest))
        .unique();
      if (existing) continue;
      await ctx.db.insert("historyChunks", chunk);
      stored++;
    }
    return { stored, skipped: args.chunks.length - stored };
  },
});
export const missing = internalQueryGeneric({
  args: { digests: v.array(v.string()) },
  handler: async (ctx, args) => {
    const out: string[] = [];
    for (const digest of args.digests) {
      const existing = await ctx.db
        .query("historyChunks")
        .withIndex("by_digest", (q) => q.eq("digest", digest))
        .unique();
      if (!existing) out.push(digest);
    }
    return out;
  },
});
export const chunk = internalQueryGeneric({
  args: { digest: v.string() },
  handler: async (ctx, args) =>
    ctx.db
      .query("historyChunks")
      .withIndex("by_digest", (q) => q.eq("digest", args.digest))
      .unique(),
});
