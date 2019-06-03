#if os(Linux)
    import Glibc
#else
    import Darwin
#endif

public struct SwiftPawn {
    public enum Errors: Error {
        case spawn(String)
        case execution(String)
        case wait(String)

        case signaled(Int32)
        case stopped(String)
        case coredumped(String)
    }

    /// Simple execution of command, the parent process will hang and wait for the child process to complete.
    ///
    /// Ideally this method should be returning status and capturing stdout and stderr contents, Swift explicitly bars user
    /// from using fork due to it's hard to get it right
    /// (which makes sense, referring to [this link](https://www.evanjones.ca/fork-is-dangerous.html))
    /// although there is a workaround to use fork in Swift
    /// (as pointed out by [this link](https://gist.github.com/bugaevc/4307eaf045e4b4264d8e395b5878a63b)) I decide not to
    /// over-complicate things here due to posix_spawn is a better way of spawning child process to run another program
    /// (referring to [this link](https://github.com/rtomayko/posix-spawn#benchmarks)).
    ///
    /// When using posix_spawn there doesn't seem to be an easy way to redirect stdout or stderr to a string, as there is
    /// not much customization we can do with posix_spawn (unlike fork where we can fully customize the child process).
    ///
    /// - Parameters:
    ///   - command: command to execute
    ///   - arguments: arguments passed in, the first argument must be the name of the command (last element after "/")
    public static func execute(command: String, arguments args: [String]) throws {
        var cpid: pid_t = 0
        let argv = args.map { $0.withCString(strdup) }

        // spawn
        var fa: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&fa)
        posix_spawn_file_actions_addclose(&fa, 3)
        posix_spawn_file_actions_addopen(&fa, 3, "/tmp/spawn_out", O_TRUNC | O_RDWR | O_CREAT, S_IRUSR | S_IWUSR)
        posix_spawn_file_actions_adddup2(&fa, 3, 1)
        
        posix_spawn_file_actions_addclose(&fa, 4)
        posix_spawn_file_actions_addopen(&fa, 4, "/tmp/spawn_err", O_TRUNC | O_RDWR | O_CREAT, S_IRUSR | S_IWUSR)
        posix_spawn_file_actions_adddup2(&fa, 4, 1)
        let pid = posix_spawnp(&cpid, command, &fa, nil, argv + [nil], environ)
        posix_spawn_file_actions_destroy(&fa)
        guard pid == 0 else {
            throw Errors.spawn("Execution of \(command) could not be started due to error code (\(pid))")
        }

        // wait
        var stat: Int32 = 0
        let wpid = waitpid(pid, &stat, 0)
        guard wpid != -1 else {
            throw Errors.wait("Waiting on child (pid:\(cpid)) failed with errno \(errno)")
        }

        // check termination reason
        let _WSTATUS = stat & 0177
        if _WSTATUS == 0 { // WIFEXITED
            #if __DARWIN_UNIX03
                let rstat = (stat >> 8) & 0x0000_00FF
            #else /* !__DARWIN_UNIX03 */
                let rstat = stat >> 8
            #endif

            if rstat != 0 {
                throw Errors.execution("Execution of \(command) failed with status (\(rstat))")
            }
        } else if _WSTATUS == _WSTOPPED { // WIFSTOPPED
            throw Errors.stopped("Execution of \(command) was stopped by signal \(stat >> 8)")
        } else { // WIFSIGNALED
            if stat & WCOREFLAG != 0 {
                throw Errors.coredumped("Core dumped when executing \(command).")
            }
            throw Errors.signaled(_WSTATUS)
        }
    }

    /// Fail fast execution of command, the parent process will not hang and doesn't care about return status of the
    /// child.
    ///
    /// - Parameters:
    ///   - command: command to execute
    ///   - arguments: arguments
    /// - Throws: _SwiftPawn.Errors_
    public static func nonBlockedExecute(command: String, arguments args: [String]) throws {
        var cpid: pid_t = 0
        let argv = args.map { $0.withCString(strdup) }

        let pid = posix_spawnp(&cpid, command, nil, nil, argv + [nil], environ)
        guard pid == 0 else {
            throw Errors.spawn("Execution of \(command) could not be started due to error code (\(pid))")
        }
    }
}
