import { spawn, type ChildProcess } from "node:child_process";
import { createInterface, type Interface } from "node:readline";

export interface TransportOptions {
  binary: string;
  /** Pass `--disclaim` so the binary becomes its own TCC responsible process. */
  disclaim?: boolean;
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

    const args = options.disclaim ? ["serve", "--disclaim"] : ["serve"];
    this.process = spawn(options.binary, args, {
      stdio: ["pipe", "pipe", "pipe"],
    });

    // Let Node's event loop exit even if user code never calls close().
    // We unref the child handle AND the stdio pipes — otherwise the readline
    // 'data' listener on stdout keeps the loop alive forever.
    // Don't unref stdin: we need it writable.
    this.process.unref();
    this.process.stdout?.unref?.();
    this.process.stderr?.unref?.();

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
      this.process = null;
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

  /**
   * Graceful: close stdin so the child sees EOF and exits on its own.
   * Returns the still-live ChildProcess so the caller can await its `exit`
   * event or escalate with kill(). Does NOT null `this.process` — the
   * `exit` handler does that, so kill() works during the escalation window.
   */
  stop(): ChildProcess | null {
    this._alive = false;
    this.rl?.close();
    this.rl = null;
    const proc = this.process;
    if (proc?.stdin?.writable) {
      try {
        proc.stdin.end();
      } catch {
        // ignore broken pipe
      }
    }
    return proc;
  }

  /** Forceful: send signal, swallow errors if the child is already dead. */
  kill(signal: NodeJS.Signals = "SIGTERM"): void {
    try {
      this.process?.kill(signal);
    } catch {
      // already dead
    }
  }

  /** Has the underlying child exited (or never started)? */
  hasExited(): boolean {
    return (
      !this.process ||
      this.process.exitCode !== null ||
      this.process.signalCode !== null
    );
  }
}
