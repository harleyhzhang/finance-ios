import { defineSchema, defineTable } from "convex/server";
import { v } from "convex/values";
export default defineSchema({
  snapshots: defineTable({
    revision: v.number(),
    capturedAt: v.string(),
    publishedAt: v.number(),
    digest: v.string(),
    envelope: v.string(),
  })
    .index("by_revision", ["revision"])
    .index("by_digest", ["digest"]),
});
