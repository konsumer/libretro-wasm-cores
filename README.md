# libretro-wasm-cores

Pre-built libretro cores as wasm `SIDE_MODULE=2` binaries for Emscripten frontends (e.g. [raylib-libretro](https://github.com/RobLoach/raylib-libretro)).

Download the latest cores from the [nightly release](../../releases/tag/nightly).

## Included cores

| System | Core | Extensions |
|---|---|---|
| Nintendo Entertainment System | fceumm | .fds .nes .unf .unif |
| Super Nintendo | snes9x | .smc .sfc .swc .fig .bs .st |
| Game Boy / Color / Advance | mgba | .gba .gb .gbc .sgb |
| Sega Genesis / Mega Drive / MS / GG | genesis_plus_gx | .bin .gen .smd .md .cue .iso .chd .m3u .sms .gg .sg |
| PC Engine / TurboGrafx-16 | mednafen_pce_fast | .pce .cue .ccd .chd .toc .m3u |
| WonderSwan / WonderSwan Color | mednafen_wswan | .ws .wsc .pc2 |
| Doom (PrBoom) | prboom | .wad .iwad .pwad .lmp .m3u |
| PlayStation (fast, software) | pcsx_rearmed | .bin .cue .img .mdf .pbp .toc .cbn .m3u .ccd .chd .iso |
| PlayStation (accurate, software) | mednafen_psx | .bin .cue .img .mdf .pbp .toc .cbn .m3u .ccd .chd .iso |

**PlayStation notes:** `pcsx_rearmed` is faster; `mednafen_psx` is more accurate. Both use software rendering — OpenGL GPU plugins are not available in wasm. Hardware-rendered PSX (`mednafen_psx_hw`) requires OpenGL 3.3 / WebGL2; it is not included here because its Emscripten build is untested.

## Using in a frontend

Each `.wasm` is a `SIDE_MODULE=2` with all standard libretro API symbols exported. Load it as a dynamic library at runtime:

```js
// Emscripten main module must be built with -sMAIN_MODULE=1
Module['dynamicLibraries'] = ['pcsx_rearmed_libretro.wasm'];
```

Or with `dlopen` from C (requires `-sALLOW_MEMORY_GROWTH=1` on the main module):

```c
void *handle = dlopen("pcsx_rearmed_libretro.wasm", RTLD_NOW);
```

The main module must link with `-sUSE_ZLIB=1` if loading `pcsx_rearmed` (it imports zlib symbols at dlopen time).

## Building locally

Requires: `emcc`, `emmake`, `jq`.

```sh
# Build one core
./build.sh pcsx_rearmed

# Build all cores (parallel)
jq -r '.cores[].name' cores.json | xargs -P4 -I{} ./build.sh {}

# Output: dist/<core>_libretro.wasm
```

## Adding a core

Add an entry to `cores.json`:

```json
{
  "name": "my_core",
  "repo": "https://github.com/libretro/my-core",
  "makefile": "Makefile",
  "subdir": "",
  "emcc_cflags": ""
}
```

Then add the core name to the `matrix.core` list in `.github/workflows/build.yml`.

## Notes

- Cores are built from `HEAD` of each upstream repo's default branch at build time (shallow clone).
- Native platform cores (Linux/macOS/Windows) are served by the [libretro buildbot](https://buildbot.libretro.com/nightly/) — this repo only covers wasm.
- GPL cores: source is available at the upstream repos linked in `cores.json`.
