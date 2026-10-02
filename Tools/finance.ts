#!/usr/bin/env node
import { estimateRSUs } from "./equity.ts";
import {
  readFileSync,
  writeFileSync,
  mkdirSync,
  existsSync,
  renameSync,
  chmodSync,
} from "node:fs";
import { resolve, dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";
import { randomBytes, createHash } from "node:crypto";
import { validateSnapshot, encrypt, decrypt } from "./snapshot.ts";
import { snapshotFromCSV } from "./csv.ts";
const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
/** The app's bundle identifier from Config/Local.xcconfig, falling back to the shared default. */
function bundleId(): string {
  for (const file of ["Config/Local.xcconfig", "Config/Finance.xcconfig"]) {
    const path = join(root, file);
    if (!existsSync(path)) continue;
    const match = readFileSync(path, "utf8").match(/^FINANCE_BUNDLE_ID *= *(\S+)/m);
    if (match) return match[1];
  }
  return "com.example.finance";
}
function run(
  command: string,
  args: string[],
  input?: string,
  quiet = false,
): string {
  const r = spawnSync(command, args, {
    cwd: root,
    input,
    encoding: "utf8",
    maxBuffer: 4e6,
  });
  if (r.status !== 0)
    throw Error(
      quiet
        ? "Command failed; secret output suppressed."
        : `${command} failed: ${r.stderr}`,
    );
  return r.stdout.trim();
}
function keychain(mode: string, input?: string) {
  const helper = join(root, "build", "finance-keychain");
  if (!existsSync(helper)) {
    mkdirSync(dirname(helper), { recursive: true });
    run("swiftc", [join(root, "Tools/keychain.swift"), "-o", helper]);
  }
  return run(helper, [mode, bundleId() + ".publisher"], input, true);
}
function credentials() {
  return JSON.parse(keychain("read")) as {
    readToken: string;
    encryptionKey: string;
  };
}
function privateWrite(path: string, data: string) {
  const destination = resolve(path);
  if (destination === root || destination.startsWith(root + "/"))
    throw Error("Private data must be outside the repository");
  mkdirSync(dirname(destination), { recursive: true, mode: 0o700 });
  writeFileSync(destination + ".tmp", data, { mode: 0o600 });
  chmodSync(destination + ".tmp", 0o600);
  renameSync(destination + ".tmp", destination);
}
function load(path: string) {
  const s = JSON.parse(readFileSync(path, "utf8"));
  validateSnapshot(s);
  return s;
}
const [command, ...args] = process.argv.slice(2);
async function main() {
  if (command === "from-csv") {
    const [accounts, history, cadPerUSD, out] = args;
    if (!accounts || !cadPerUSD || !out)
      throw Error("Usage: from-csv ACCOUNTS.csv HISTORY.csv|- CAD_PER_USD OUT.json");
    const s = snapshotFromCSV(
      readFileSync(accounts, "utf8"),
      history === "-" ? "" : readFileSync(history, "utf8"),
      cadPerUSD,
    );
    privateWrite(out, JSON.stringify(s, null, 2));
    console.log(`Snapshot written: ${s.accounts.length} accounts, ${s.history.length} history points.`);
  } else if (command === "estimate-rsus") {
    const input = JSON.parse(readFileSync(args[0], "utf8"));
    const account = estimateRSUs(input);
    privateWrite(args[1], JSON.stringify(account, null, 2));
    console.log("Validated RSU estimate written privately; nothing published.");
  } else if (command === "init-keys") {
    // Creation intentionally refuses to replace an existing Keychain item.
    keychain(
      "create",
      JSON.stringify({
        readToken: randomBytes(32).toString("base64url"),
        encryptionKey: randomBytes(32).toString("base64"),
      }),
    );
    console.log("Created production secrets in macOS Keychain.");
  } else if (command === "validate") {
    const s = load(args[0]);
    console.log(
      JSON.stringify({
        valid: true,
        asOf: s.asOf,
        accounts: s.accounts.length,
        history: s.history.length,
        from: s.history[0]?.date,
        to: s.history.at(-1)?.date,
      }),
    );
  } else if (command === "prepare") {
    const s = load(args[0]),
      c = credentials(),
      e = encrypt(s, Buffer.from(c.encryptionKey, "base64"));
    if (
      JSON.stringify(
        decrypt(e.envelope, Buffer.from(c.encryptionKey, "base64")),
      ) !== JSON.stringify(s)
    )
      throw Error("Encryption verification failed");
    privateWrite(args[1], JSON.stringify(e));
    console.log("Validated and encrypted snapshot; nothing published.");
  } else if (command === "configure-read-token") {
    const hash = createHash("sha256")
      .update(credentials().readToken)
      .digest("hex");
    run("npx", [
      "convex",
      "env",
      "set",
      "FINANCE_READ_TOKEN_SHA256",
      hash,
      "--prod",
    ]);
    console.log("Production read-token hash configured.");
  } else if (command === "profile") {
    const endpoint = args[0];
    const u = new URL(endpoint);
    if (
      u.protocol !== "https:" ||
      !u.hostname.endsWith(".convex.site") ||
      u.pathname !== "/v1/snapshot" ||
      u.username ||
      u.password ||
      u.port ||
      u.search ||
      u.hash
    )
      throw Error("Invalid endpoint");
    privateWrite(
      args[1],
      JSON.stringify({ version: 1, endpoint, ...credentials() }),
    );
    console.log("Private connection profile written; treat it as a password.");
  } else if (command === "publish") {
    const prepared = JSON.parse(readFileSync(args[0], "utf8"));
    const clear = decrypt(
      prepared.envelope,
      Buffer.from(credentials().encryptionKey, "base64"),
    );
    const bytes = Buffer.from(JSON.parse(prepared.envelope).combined, "base64");
    if (
      createHash("sha256").update(bytes).digest("hex") !== prepared.digest ||
      clear.capturedAt !== prepared.capturedAt
    )
      throw Error("Invalid prepared envelope");
    const expected = Number(args[1]);
    if (!Number.isSafeInteger(expected) || expected < 0)
      throw Error("Supply expected revision from status");
    const output = run("npx", [
      "convex",
      "run",
      "snapshots:publish",
      JSON.stringify({ ...prepared, expectedRevision: expected }),
      "--prod",
    ]);
    console.log(output);
  } else if (command === "status") {
    console.log(
      run("npx", ["convex", "run", "snapshots:status", "{}", "--prod"]),
    );
  } else if (command === "verify-remote") {
    const c = credentials(),
      endpoint = args[0],
      url = new URL(endpoint);
    if (
      url.protocol !== "https:" ||
      !url.hostname.endsWith(".convex.site") ||
      url.pathname !== "/v1/snapshot" ||
      url.username ||
      url.password ||
      url.search ||
      url.hash ||
      url.port
    )
      throw Error("Invalid endpoint");
    const anonymous = await fetch(endpoint, { redirect: "error" });
    if (anonymous.status !== 401) throw Error("Anonymous access not rejected");
    const response = await fetch(endpoint, {
      headers: { authorization: "Bearer " + c.readToken },
      redirect: "error",
    });
    if (!response.ok)
      throw Error("Authenticated read failed: " + response.status);
    const body = (await response.json()) as any,
      combined = Buffer.from(body.envelope.combined, "base64");
    if (createHash("sha256").update(combined).digest("hex") !== body.digest)
      throw Error("Digest mismatch");
    const s = decrypt(
      JSON.stringify(body.envelope),
      Buffer.from(c.encryptionKey, "base64"),
    );
    if (s.capturedAt !== body.capturedAt) throw Error("Capture mismatch");
    const unchanged = await fetch(endpoint, {
      headers: {
        authorization: "Bearer " + c.readToken,
        "if-none-match": '"' + body.digest + '"',
      },
      redirect: "error",
    });
    if (unchanged.status !== 304) throw Error("Conditional read failed");
    const write = await fetch(endpoint, {
      method: "POST",
      headers: { authorization: "Bearer " + c.readToken },
      redirect: "error",
    });
    if (write.status < 400) throw Error("Unexpected writable route");
    console.log(
      JSON.stringify({
        verified: true,
        revision: body.revision,
        accounts: s.accounts.length,
        history: s.history.length,
        anonymous: anonymous.status,
        unchanged: unchanged.status,
        write: write.status,
      }),
    );
  } else if (command === "simulator") {
    const s = load(args[0]),
      device = args[1] ?? "booted";
    const container = run("xcrun", [
      "simctl",
      "get_app_container",
      device,
      bundleId(),
      "data",
    ]);
    const dest = join(container, "Documents");
    mkdirSync(dest, { recursive: true });
    // Explicit local replacement resets cache metadata so the supplied seed is authoritative.
    privateWrite(
      join(dest, "cache-v2.json"),
      JSON.stringify({ revision: 0, digest: null, snapshot: s }),
    );
    spawnSync("xcrun", ["simctl", "terminate", device, bundleId()], {
      stdio: "ignore",
    });
    run("xcrun", ["simctl", "launch", device, bundleId()]);
    console.log("Local simulator seed installed and app relaunched.");
  } else
    throw Error(
      "Usage: node Tools/finance.ts from-csv ACCOUNTS HISTORY|- CAD_PER_USD OUT | validate SNAPSHOT | simulator SNAPSHOT [UDID] | init-keys | configure-read-token | profile ENDPOINT OUT.financeprofile | prepare SNAPSHOT ENVELOPE | status | publish ENVELOPE EXPECTED_REVISION | verify-remote ENDPOINT | estimate-rsus INPUT OUT",
    );
}
main().catch((error) => {
  console.error(error.message);
  process.exitCode = 1;
});
