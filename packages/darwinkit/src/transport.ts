import { spawn, type ChildProcess } from "node:child_process";
import { createInterface, type Interface } from "node:readline";

export interface TransportOptions {
  binary: string;
  onLine: (line: string) => void;
  onExit: (code: number | null) => void;
  onError: (error: Error) => void;
}

export class Transport {
  private process: ChildProcess | null = null;
  private rl: Interface | null = null;
  private _alive = false;

  get alive(): boolean {
    return this._alive;
  }

  start(options: TransportOptions): void {
    if (this._alive) {
      throw new Error("Transport already started");
    }

    this.process = spawn(options.binary, ["serve"], {
      stdio: ["pipe", "pipe", "pipe"],
    });

    this._alive = true;

    this.rl = createInterface({ input: this.process.stdout! });
    this.rl.on("line", options.onLine);

    this.process.on("error", (err: Error) => {
      this._alive = false;
      options.onError(err);
    });

    this.process.on("exit", (code: number | null) => {
      this._alive = false;
      this.rl?.close();
      this.rl = null;
      options.onExit(code);
    });

    // Pipe stderr for debugging
    this.process.stderr?.on("data", () => {
      // stderr is debug output from darwinkit, ignore by default
    });
  }

  writeLine(json: string): void {
    if (!this._alive || !this.process?.stdin?.writable) {
      throw new Error("Transport not connected");
    }
    this.process.stdin.write(json + "\n");
  }

  stop(): void {
    this._alive = false;
    this.rl?.close();
    this.rl = null;
    if (this.process?.stdin?.writable) {
      this.process.stdin.end();
    }
    this.process = null;
  }
}
