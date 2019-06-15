#if os(Linux)
  import Glibc
#else
  import Darwin
#endif

// MARK: - Errors

public enum Errors: Error {
  case spawn(String)
  case execution(String)
  case wait(String)

  case signaled(Int32)
  case stopped(String)
  case coredumped(String)

  case io(String)
}

// MARK: - SwiftPawn

public struct SwiftPawn {
  private static let BufferSize = 4096

  /// Simple execution of command, the parent process will hang and wait for the child process to complete.
  ///
  /// Initially, I tried to use fork but Swift explicitly bars user from using fork due to it's hard to get it right
  /// (which makes sense, referring to [this link](https://www.evanjones.ca/fork-is-dangerous.html))
  /// although there is a workaround to use fork in Swift
  /// (as pointed out by [this link](https://gist.github.com/bugaevc/4307eaf045e4b4264d8e395b5878a63b)) I decide not to
  /// over-complicate things here due to posix_spawn is a better way of spawning child process to run another program
  /// (referring to [this link](https://github.com/rtomayko/posix-spawn#benchmarks)).
  ///
  /// - Parameters:
  ///   - command: command to execute
  ///   - arguments: arguments passed in, the first argument must be the name of the command (last element after "/")
  /// - Returns: program exit status, captured stdout/stderr
  public static func execute(command: String, arguments args: [String]) throws -> (Int32, String, String) {
    var cpid: pid_t = 0
    let argv = args.map { $0.withCString(strdup) }

    // pipes
    var pout = [Int32](repeating: 0, count: 2)
    var ret = pipe(&pout)
    if ret != 0 {
      throw Errors.io("Failure to create pipe for stdout error code: \(ret)")
    }
    var perr = [Int32](repeating: 0, count: 2)
    ret = pipe(&perr)
    if ret != 0 {
      throw Errors.io("Failure to create pipe for stderr error code: \(ret)")
    }

    // spawn
    var g = SystemRandomNumberGenerator()
    let randomNum = g.next()
    var fa: posix_spawn_file_actions_t!
    posix_spawn_file_actions_init(&fa)

    // setup stdout redirection
    posix_spawn_file_actions_addclose(&fa, pout[0])
    posix_spawn_file_actions_adddup2(&fa, pout[1], 1)
    posix_spawn_file_actions_addclose(&fa, pout[1])

    // setup stderr redirection
    posix_spawn_file_actions_addclose(&fa, perr[0])
    posix_spawn_file_actions_adddup2(&fa, perr[1], 2)
    posix_spawn_file_actions_addclose(&fa, perr[1])

    let pid = posix_spawnp(&cpid, command, &fa, nil, argv + [nil], environ)
    defer { posix_spawn_file_actions_destroy(&fa) }
    guard pid == 0 else {
      throw Errors.spawn("Execution of \(command) could not be started due to error code (\(pid))")
    }

    defer { close(pout[0]) }
    close(pout[1])

    defer { close(perr[0]) }
    close(perr[1])

    // read redirected stdout/stderr, need to go before wait to make sure we consume all the data
    let out = try readAll(pout[0])
    let err = try readAll(perr[0])

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

      return (rstat, out, err)
    } else if _WSTATUS == WSTOPPED { // WIFSTOPPED
      throw Errors.stopped("Execution of \(command) was stopped by signal \(stat >> 8)")
    } else { // WIFSIGNALED
      if stat & WCOREFLAG != 0 {
        throw Errors.coredumped("Core dumped when executing \(command).")
      }
      throw Errors.signaled(_WSTATUS)
    }
  }

  private static func readAll(_ fd: Int32) throws -> String {
    var result = ""

    var buffer = UnsafeMutablePointer<Int8>.allocate(capacity: BufferSize)
    buffer.initialize(to: 0)
    defer { buffer.deinitialize(count: BufferSize) }
    defer { buffer.deallocate() }

    while true {
      memset(buffer, 0, BufferSize)
      let ret = read(fd, buffer, BufferSize - 1)
      if ret < 0 {
        throw Errors.io("Error reading from fd: \(fd), errno: \(errno)")
      }

      result += String(cString: buffer)

      if ret == 0 {
        break
      }
    }

    return result
  }
}
