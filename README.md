Build C implementation

```sh
zig run -lc build.c
```

Build Zig implementation

```sh
zig build -Doptimize=ReleaseFast run -- main.bb main.cmd
```
