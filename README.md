Build C implementation

```sh
zig run -lc build.c
zig run -lc build.c -- release
```

Build Zig implementation

```sh
zig build run
zig build -Doptimize=ReleaseFast
zig build -Doptimize=ReleaseFast -Dtarget=x86_64-linux-musl
zig build -Doptimize=ReleaseFast -Dtarget=x86_64-windows
```
