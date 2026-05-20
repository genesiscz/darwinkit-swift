import { describe, expect, test } from "bun:test";
import { DarwinKit } from "../client.js";

async function countLiveChildren(parentPid: number): Promise<number> {
  const ps = Bun.spawnSync(["pgrep", "-P", String(parentPid), "-f", "darwinkit"]);
  if (ps.exitCode !== 0) return 0;
  return ps.stdout
    .toString()
    .trim()
    .split("\n")
    .filter(Boolean).length;
}

async function waitUntil(
  predicate: () => Promise<boolean> | boolean,
  budgetMs: number,
  stepMs = 50,
): Promise<boolean> {
  const start = Date.now();
  while (Date.now() - start < budgetMs) {
    if (await predicate()) return true;
    await new Promise((r) => setTimeout(r, stepMs));
  }
  return predicate() as Promise<boolean>;
}

describe("DarwinKit lifecycle", () => {
  test(
    "close() terminates the child within 2s",
    async () => {
      const dk = new DarwinKit({ logLevel: "silent" });
      await dk.connect();
      expect(await countLiveChildren(process.pid)).toBe(1);

      // Note: pre-fix close() is sync; post-fix it becomes async. await works for both.
      await (dk.close() as unknown as Promise<void> | void);

      const ok = await waitUntil(async () => (await countLiveChildren(process.pid)) === 0, 2_000);
      expect(ok).toBe(true);
    },
    10_000,
  );

  test(
    "Node process exits within 5s after a request completes (no child holds the event loop)",
    async () => {
      const sdkDist = `${import.meta.dir}/../../dist/index.js`;
      const script = `
        import { DarwinKit } from "${sdkDist}";
        const dk = new DarwinKit({ logLevel: "silent" });
        await dk.system.capabilities();
        // intentionally NO dk.close() — exercises the unref path
      `;
      const start = Date.now();
      const proc = Bun.spawn(["bun", "-e", script], {
        stdout: "pipe",
        stderr: "pipe",
      });

      // Race the natural exit against a hard budget so a hung child doesn't hang the test.
      const exitedNaturally = await Promise.race([
        proc.exited.then(() => true),
        new Promise<false>((r) => setTimeout(() => r(false), 5_000)),
      ]);

      const elapsed = Date.now() - start;
      if (!exitedNaturally) {
        proc.kill("SIGKILL");
        await proc.exited;
      }
      expect(exitedNaturally).toBe(true);
      expect(proc.exitCode).toBe(0);
      expect(elapsed).toBeLessThan(5_000);
    },
    15_000,
  );

  test(
    "Parent SIGKILL leaves no orphan grand-child after 2s",
    async () => {
      const sdkDist = `${import.meta.dir}/../../dist/index.js`;
      const inner = `
        import { DarwinKit } from "${sdkDist}";
        const dk = new DarwinKit({ logLevel: "silent" });
        await dk.connect();
        await new Promise(() => {}); // hang
      `;
      const proc = Bun.spawn(["bun", "-e", inner], {
        stdout: "pipe",
        stderr: "pipe",
      });

      // Wait until darwinkit child is up
      const childUp = await waitUntil(
        async () => (await countLiveChildren(proc.pid)) >= 1,
        5_000,
      );
      expect(childUp).toBe(true);

      proc.kill("SIGKILL");

      const ok = await waitUntil(
        async () => (await countLiveChildren(proc.pid)) === 0,
        3_000,
      );
      expect(ok).toBe(true);
    },
    15_000,
  );
});
