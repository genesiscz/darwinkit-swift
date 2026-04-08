import { execSync } from "node:child_process";
import { existsSync, mkdirSync, chmodSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { homedir } from "node:os";
import { Readable } from "node:stream";
import { pipeline } from "node:stream/promises";
import { createGunzip } from "node:zlib";
import { extract } from "tar";

const BINARY_NAME = "darwinkit";
const APP_BUNDLE_PATH = "DarwinKit.app/Contents/MacOS/darwinkit";
const CACHE_DIR = join(homedir(), ".cache", "darwinkit");
const RELEASE_URL =
  "https://github.com/genesiscz/darwinkit-swift/releases/latest/download/darwinkit-macos-arm64.tar.gz";
const REPO_URL = "https://github.com/genesiscz/darwinkit-swift.git";

/** Resolve the directory where this module lives (works in both ESM and CJS). */
function getPackageDir(): string {
  try {
    // ESM
    return dirname(fileURLToPath(import.meta.url));
  } catch {
    // CJS fallback
    return __dirname;
  }
}

export async function ensureBinary(binaryPath?: string): Promise<string> {
  // 1. Explicit path
  if (binaryPath) {
    if (!existsSync(binaryPath)) {
      throw new Error(`Binary not found at specified path: ${binaryPath}`);
    }
    return binaryPath;
  }

  // 2. Check bundled .app bundle (shipped with npm package, enables notifications)
  const bundledApp = join(getPackageDir(), "..", "bin", APP_BUNDLE_PATH);
  if (existsSync(bundledApp)) return bundledApp;

  // 3. Check bundled standalone binary
  const bundled = join(getPackageDir(), "..", "bin", BINARY_NAME);
  if (existsSync(bundled)) return bundled;

  // 4. Check PATH
  const fromPath = findOnPath(BINARY_NAME);
  if (fromPath) return fromPath;

  // 5. Check cached .app bundle
  const cachedApp = join(CACHE_DIR, APP_BUNDLE_PATH);
  if (existsSync(cachedApp)) return cachedApp;

  // 6. Check cached standalone binary
  const cached = join(CACHE_DIR, BINARY_NAME);
  if (existsSync(cached)) return cached;

  // 7. Download from GitHub releases
  mkdirSync(CACHE_DIR, { recursive: true });

  try {
    console.error(
      "[darwinkit] Binary not found, downloading from GitHub releases...",
    );
    await downloadAndExtract(RELEASE_URL, CACHE_DIR);
    chmodSync(cached, 0o755);
    console.error("[darwinkit] Binary downloaded to", cached);
    return cached;
  } catch (downloadError) {
    console.error("[darwinkit] Download failed:", downloadError);
  }

  // 8. Build from source
  if (findOnPath("swift")) {
    try {
      console.error("[darwinkit] Attempting to build from source...");
      return await buildFromSource(cached);
    } catch (buildError) {
      console.error("[darwinkit] Build from source failed:", buildError);
    }
  }

  // 9. Fail with instructions
  throw new Error(
    "Could not find or install darwinkit binary.\n" +
      "Install it manually:\n" +
      "  curl -L https://github.com/genesiscz/darwinkit-swift/releases/latest/download/darwinkit-macos-arm64.tar.gz | tar xz -C ~/.local/bin/\n" +
      "Or set the binary path:\n" +
      "  new DarwinKit({ binary: '/path/to/darwinkit' })",
  );
}

function findOnPath(name: string): string | null {
  try {
    return execSync(`which ${name}`, {
      encoding: "utf-8",
      stdio: ["pipe", "pipe", "pipe"],
    }).trim();
  } catch {
    return null;
  }
}

async function downloadAndExtract(url: string, destDir: string): Promise<void> {
  const response = await fetch(url, { redirect: "follow" });
  if (!response.ok) {
    throw new Error(`HTTP ${response.status}: ${response.statusText}`);
  }
  if (!response.body) {
    throw new Error("No response body");
  }

  const nodeStream = Readable.fromWeb(response.body as any);
  await pipeline(nodeStream, createGunzip(), extract({ cwd: destDir }));
}

async function buildFromSource(outputPath: string): Promise<string> {
  const { execSync } = await import("node:child_process");
  const tmpDir = execSync("mktemp -d", { encoding: "utf-8" }).trim();

  try {
    execSync(`git clone --depth 1 ${REPO_URL} "${tmpDir}/darwinkit-swift"`, {
      stdio: "pipe",
    });

    execSync("swift build -c release --arch arm64", {
      cwd: join(tmpDir, "darwinkit-swift", "packages", "darwinkit-swift"),
      stdio: "pipe",
      timeout: 300_000, // 5 min build timeout
    });

    const builtBinary = join(
      tmpDir,
      "darwinkit-swift",
      "packages",
      "darwinkit-swift",
      ".build",
      "arm64-apple-macosx",
      "release",
      "darwinkit",
    );
    const { copyFileSync } = await import("node:fs");
    copyFileSync(builtBinary, outputPath);
    chmodSync(outputPath, 0o755);
    console.error("[darwinkit] Built from source and cached at", outputPath);
    return outputPath;
  } finally {
    try {
      execSync(`rm -rf "${tmpDir}"`, { stdio: "pipe" });
    } catch {}
  }
}
