# SwiftPawn

Swift implementation for easy fork + exec. This implementation is Foundation-free.

__Note:__ Currently doesn't support redirecting stdout/stderr. 

# Usage

## Add Dependency

```Swift
.package(url: "https://github.com/hanjoes/Termbo", from: "0.1.0")
```

## API Usage

```Swift
do {
    try SwiftPawn.execute(command: "git", arguments: ["git", "status"])
} catch {
    print(error)
}
```

