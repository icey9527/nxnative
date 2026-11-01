# Red Alert 2 runtime on iOS 16

The full owned EA archive needs both a compatible WebAssembly runtime and the
game's Blowfish COM registration. Importing a ZIP installs neither dependency.
The app runs `cmd.exe /c regsvr32.exe /s Blowfish.dll && gamemd.exe` from the
mounted game directory. Registration uses Wine's normal persistent prefix; it
does not copy EA account state or change host permissions. Failure stops launch.

For iPadOS 16.1 the checked build is official BoxedWine commit
`2be9ff442feac29755a46693cd989960eeac8786`, Emscripten 4.0.23, with
`make release WASM_EXCEPTIONS_FLAG=-fwasm-exceptions TAIL_CALL_FLAG= MAKEFLAGS=-j4`.
The resulting Wasm has no SIMD, tail-call, new exception-reference, or GC
instructions. Merely enabling legacy Wasm exceptions on the JIT build is
insufficient: that build still contains SIMD and tail calls. Do not lower an
Info.plist deployment version to declare those binaries compatible.

The release Wasm SHA-256 is
`b95d8088d70f29cc997a2448d045f57adb6709b9fd87a42c92494c9f2a84610c`.
Bundle the upstream GPL license, corresponding-source revision, build flags and
local shell parser changes with the runtime. Keep the stable localhost origin
and persistent WebKit data store so an app update preserves Wine's saved data.

Validation on 2026-11-01: static instruction audit, compilation with exnref
explicitly disabled, non-game COM registration and query, and the exact Windows
`cmd.exe` registration/query launch sequence passed. The iOS 16.1 app compiled
and was installed on an M2 iPad. Runtime and full owned archive hashes were read
back; ten save files and 84 CPU tables stayed unchanged. No commercial game was
automatically launched. These checks do not establish campaign playability or
interpreter performance; those remain user tests. The official Wine test harness
did not produce a unit-test summary, so its timeout is not a passing Wine suite.
