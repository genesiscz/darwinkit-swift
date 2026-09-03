import Darwin
import Foundation

/// Private libSystem API, used by Chromium, kitty and WezTerm: the spawned child becomes its own
/// TCC "responsible process" instead of inheriting the launcher's identity.
@_silgen_name("responsibility_spawnattrs_setdisclaim")
private func responsibility_spawnattrs_setdisclaim(_ attrs: UnsafeMutablePointer<posix_spawnattr_t?>, _ disclaim: Int32) -> Int32

/// Re-spawns the current executable once with the disclaim attribute and proxies its exit status.
///
/// Why: macOS TCC keys Calendar, Reminders and Contacts grants to the responsible process, which
/// for a CLI is the terminal app that launched it. A disclaimed re-spawn makes DarwinKit.app (this
/// bundle) the client, so one grant serves every terminal and every launchd job.
enum Disclaim {
    static let marker = "DARWINKIT_DISCLAIMED"
    private static var childPid: pid_t = 0

    static func respawnIfNeeded() {
        let env = ProcessInfo.processInfo.environment
        if env[marker] == "1" {
            return
        }

        guard let executable = Bundle.main.executablePath ?? CommandLine.arguments.first else {
            warn("cannot resolve own executable for --disclaim")
            return
        }

        var attrs: posix_spawnattr_t? = nil
        guard posix_spawnattr_init(&attrs) == 0 else {
            warn("posix_spawnattr_init failed, running undisclaimed")
            return
        }
        defer { posix_spawnattr_destroy(&attrs) }

        let rc = responsibility_spawnattrs_setdisclaim(&attrs, 1)
        if rc != 0 {
            warn("setdisclaim failed (\(rc)), running undisclaimed")
            return
        }

        var argv: [UnsafeMutablePointer<CChar>?] = CommandLine.arguments.map { strdup($0) }
        argv.append(nil)
        var envp: [UnsafeMutablePointer<CChar>?] = env.map { strdup("\($0.key)=\($0.value)") }
        envp.append(strdup("\(marker)=1"))
        envp.append(nil)
        defer {
            argv.forEach { free($0) }
            envp.forEach { free($0) }
        }

        var pid: pid_t = 0
        let spawnRc = posix_spawn(&pid, executable, nil, &attrs, argv, envp)
        if spawnRc != 0 {
            warn("disclaimed posix_spawn failed (\(spawnRc)), running undisclaimed")
            return
        }

        childPid = pid
        forwardSignalsToChild()
        watchParentDeath()

        var status: Int32 = 0
        while waitpid(pid, &status, 0) == -1 {
            if errno != EINTR {
                exit(1)
            }
        }

        if status & 0x7f != 0 {
            exit(128 + (status & 0x7f))
        }

        exit((status >> 8) & 0xff)
    }

    private static func warn(_ message: String) {
        FileHandle.standardError.write(Data("darwinkit: \(message)\n".utf8))
    }

    private static func forwardSignalsToChild() {
        for sig in [SIGINT, SIGTERM, SIGHUP, SIGQUIT] {
            signal(sig) { received in
                if Disclaim.childPid > 0 {
                    kill(Disclaim.childPid, received)
                }
            }
        }
    }

    /// macOS has no PR_SET_PDEATHSIG: if the SDK process that spawned us dies, take the child down too.
    private static func watchParentDeath() {
        let parent = getppid()
        DispatchQueue.global(qos: .utility).async {
            let kq = kqueue()
            if kq == -1 {
                return
            }

            var change = kevent(
                ident: UInt(parent), filter: Int16(EVFILT_PROC), flags: UInt16(EV_ADD | EV_ONESHOT),
                fflags: UInt32(NOTE_EXIT), data: 0, udata: nil
            )
            var event = kevent()
            if kevent(kq, &change, 1, &event, 1, nil) > 0, Disclaim.childPid > 0 {
                kill(Disclaim.childPid, SIGTERM)
            }
        }
    }
}
