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

        case io(String)
    }

    private static let StdoutFileBase = "/tmp/swfit_pawn_stdout"

    private static let StderrFileBase = "/tmp/swift_pawn_stderr"

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
    /// - Returns: program exit status, captured stdout/stderr
    public static func execute(command: String, arguments args: [String]) throws -> (Int32, String, String) {
        var cpid: pid_t = 0
        let argv = args.map { $0.withCString(strdup) }

        // spawn
        var g = SystemRandomNumberGenerator()
        let randomNum = g.next()
        var fa: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&fa)
        posix_spawn_file_actions_addclose(&fa, 3)
        let fout = "\(StdoutFileBase)_\(randomNum)"
        posix_spawn_file_actions_addopen(&fa, 3, fout, O_TRUNC | O_RDWR | O_CREAT, S_IRUSR | S_IWUSR)
        posix_spawn_file_actions_adddup2(&fa, 3, 1)

        posix_spawn_file_actions_addclose(&fa, 4)
        let ferr = "\(StderrFileBase)_\(randomNum)"
        posix_spawn_file_actions_addopen(&fa, 4, ferr, O_TRUNC | O_RDWR | O_CREAT, S_IRUSR | S_IWUSR)
        posix_spawn_file_actions_adddup2(&fa, 4, 2)
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

            return (rstat, try readAll(fout), try readAll(ferr))
        } else if _WSTATUS == _WSTOPPED { // WIFSTOPPED
            throw Errors.stopped("Execution of \(command) was stopped by signal \(stat >> 8)")
        } else { // WIFSIGNALED
            if stat & WCOREFLAG != 0 {
                throw Errors.coredumped("Core dumped when executing \(command).")
            }
            throw Errors.signaled(_WSTATUS)
        }
    }

    private static func readAll(_ path: String) throws -> String {
        let fd = fopen(path, "r")
        defer { fclose(fd) }
        
        guard fd != nil else {
            throw Errors.io("Opening stdout file \(path) failed with status \(errno)")
        }
        
        fseek(fd, 0, SEEK_END)
        let size = ftell(fd)
        rewind(fd)
                
        guard size > 0 else {
            return ""
        }
        
        // "size + 1" to include the "NULL byte"
        var buffer = [UInt8](repeating: 0, count: size + 1)
        let n = fread(&buffer, 1, size, fd)
        if n < 0 {
            throw Errors.io("File path has \(size) bytes, but fread returned \(n), errno(\(errno)")
        }
        return String(cString: buffer)
    }
}
