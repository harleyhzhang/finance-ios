import { internalMutationGeneric, internalQueryGeneric } from "convex/server";
import { v } from "convex/values";
import { nextRevision, validateEnvelope } from "./policy";
// Internal only: accessible to the authenticated deployment administrator, never the phone.
export const publish = internalMutationGeneric({
  args: {
    envelope: v.string(),
    digest: v.string(),
    capturedAt: v.string(),
    expectedRevision: v.number(),
  },
  handler: async (ctx, args) => {
    validateEnvelope(args.envelope, args.digest, args.capturedAt);
    const duplicate = await ctx.db
      .query("snapshots")
      .withIndex("by_digest", (q) => q.eq("digest", args.digest))
      .unique();
    if (duplicate)
      return {
        revision: duplicate.revision,
        digest: duplicate.digest,
        duplicate: true,
      };
    const latest = await ctx.db
      .query("snapshots")
      .withIndex("by_revision")
      .order("desc")
      .first();
    const revision = nextRevision(
      latest as { revision: number; capturedAt: string } | null,
      args.expectedRevision,
      args.capturedAt,
    );
    await ctx.db.insert("snapshots", {
      revision,
      capturedAt: args.capturedAt,
      publishedAt: Date.now(),
      digest: args.digest,
      envelope: args.envelope,
    });
    return { revision, digest: args.digest, duplicate: false };
  },
});
export const latest = internalQueryGeneric({
  args: {},
  handler: async (ctx) =>
    ctx.db.query("snapshots").withIndex("by_revision").order("desc").first(),
});
export const status = internalQueryGeneric({
  args: {},
  handler: async (ctx) => {
    const latest = await ctx.db
      .query("snapshots")
      .withIndex("by_revision")
      .order("desc")
      .first();
    return latest
      ? {
          revision: latest.revision,
          capturedAt: latest.capturedAt,
          digest: latest.digest,
        }
      : { revision: 0 };
  },
});
