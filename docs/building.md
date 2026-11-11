# Building from source

You need Windows, Visual Studio 2022 with the C++ desktop workload, JDK 21, Python 3.10+ and Git Bash.
Put the repos side by side:

```
<root>\witcher3-coop            this repo (any folder name)
<root>\WitcherOnline            Emillock/WitcherOnline, branch shared-enemies (remastered-5.01 for v0.1.0); without it,
                                the tools use this repo's WitcherOnline submodule (git submodule update --init)
<root>\WitcherNativeBridge      rejuvenate7/WitcherNativeBridge (master supports 5.01; the 5.0.0.1090142 fix is a local
                                commit, its source in the package's W3Coop\source\WitcherNativeBridge.zip)
<root>\deps\ultimate-asi-loader-9.7.4\dinput8.dll and LICENSE
                                from Ultimate-ASI-Loader-NoPDB_x64.zip, ThirteenAG/Ultimate-ASI-Loader v9.7.4
```

Run these from a Developer Command Prompt:

```bat
cd <root>\WitcherNativeBridge
msbuild WitcherNativeBridge.sln -p:Configuration=Release -p:Platform=x64

rem The client project's own OutDir points at a GOG install, so override it.
cd <root>\WitcherOnline\client
msbuild MultiplayerClient.sln -p:Configuration=Release -p:Platform=x64 -p:OutDir=<root>\WitcherOnline\client\build\Release\

cd <root>\WitcherOnline\server
mkdir build\classes
javac -encoding UTF-8 -d build\classes src\*.java
cd build\classes && jar cfm ..\WitcherServer.jar ..\..\src\META-INF\MANIFEST.MF *.class

cd <root>\witcher3-coop
relay\build.cmd
w3test\build.cmd
python package\build_package.py 0.4.0
```

`relay\build.cmd` also builds and runs the relay helpers' own tests (`tests\test_relay_xml.cpp`,
`tests\test_port_arg.cpp`), so a broken helper fails the build instead of going unnoticed.

The last step writes `<root>\work\dist\W3Coop-0.4.0` and its zip. [config.py](config.py) finds the game
through Steam's library folders. You can override paths with `W3_GAME_DIR`, `W3C_ROOT` and `W3C_WORK`.

## The mod's text

The mod's strings live in `WitcherOnline\witcher\mods\modWitcherOnline\content\en.csv`. After editing it, run
`mod_strings.py` to rewrite the eighteen `.w3strings` tables beside it, one per language the game ships, each
under its own language key. `w3strings.py decode <file>` reads any of them, the game's own included, and its
header comment describes the format. A table in the 4.x format, or one written under another language's key,
resolves to nothing in game: that is a silent failure, so `run_test.py` prints a STRINGS line at every bot's
start saying whether the mod's own ids and keys decode.

## Repo layout

| Path | Contents |
|---|---|
| `WitcherOnline/` | Submodule: the mod (the Emillock/WitcherOnline fork, GPL-3.0), pinned to the tested `shared-enemies` commit |
| `relay/` | w3relay (host and join), the mock `steam_api64.dll` for one-PC tests, self-test |
| `package/` | Package builder, `Host co-op.cmd`, `Join co-op.cmd`, player README |
| `w3test/` | The test bot: ASI (test-mode hooks, env natives) and script mod (scenarios) |
| `run_test.py`, `w3run.py`, `sandbox.py`, `preset_expand.py`, `deploy.py`, `compile.sh` | Harness |
| `ws_*_check.py`, `wnb_static_check.py`, `port_edits/`, `exe_strings.py`, `pe_imports.py` | Static checks and scripted edits used during the port |
| `docs/` | Design notes |
