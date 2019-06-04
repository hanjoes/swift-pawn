# SwiftPawn

Swift implementation for easy fork + exec. This implementation is Foundation-free.



# Usage

## Add Dependency

```Swift
.package(url: "https://github.com/hanjoes/Termbo", from: "0.1.0")
```

## API Usage

```Swift
do {
    let (status, out, err) = try SwiftPawn.execute(command: "git", arguments: ["git", "status"])
} catch {
    print(error)
}
```

