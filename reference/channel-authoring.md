# Authoring ushell channels

ushell is extensible. New commands live in **channels** — subdirectories under `channels/` containing a `describe.flow.py` declaration + per-command Python files. The build system enumerates channels at boot, hashes them into a binary manifest, and loads them lazily.

## Why author a channel?

- Add project-specific commands (`.mychan generate-data`, `.mychan resave-with-validation`).
- Override or extend existing commands by registering the same `.invoke()` words and chaining via `super().main()`.
- Ship build-pipeline helpers alongside the project (`.mychan ship`, `.mychan smoke-test`).

## Channel layout

```
channels/
  mychan/
    describe.flow.py          # required - declares the channel & its commands
    cmds/
      resave.py               # one file per command class
      ship.py
    pylib/                    # optional - auto-added to sys.path
      mychan/
        helpers.py
    boot.py                   # optional - runs at session boot
    prompt.py                 # optional - customises the prompt
    tips.py                   # optional - registers $tip entries
```

**Channel naming:** derived from the directory tree. `channels/mychan/` becomes `mychan`. Multi-word: `channels/mr/hayes/` becomes `mr.hayes`. Lowercase directories.

**`pylib/<name>/` convention:** a channel's `pylib/` is auto-added to `sys.path`, so any command can `import mychan.helpers`. This is how core ushell ships `unrealcmd`, `unreal.*`, and `uelogprinter` for use across commands.

## The flow framework

Channels build on three core classes from `flow.describe`:

- **`flow.describe.Channel()`** — terminal object in every `describe.flow.py`. Declares the channel itself: parent, version, optional pips (deprecated).
- **`flow.describe.Command()`** — binds a Python class to an invocation path (a sequence of words on the command line).
- **`flow.describe.Tool()`** — declares external binaries to be downloaded, sha1-verified, and exposed on PATH via shims.

Commands inherit from `flow.cmd.Cmd` (or its UE-aware subclass `unrealcmd.Cmd` / `unrealcmd.MultiPlatformCmd`). Args and Opts are declared as class attributes via `flow.cmd.Arg(...)` / `flow.cmd.Opt(...)`.

Source: `<ushell>/channels/flow/core/system/flow/describe.py`, `cmd.py`.

---

## describe.flow.py annotated

A working, minimal `describe.flow.py`:

```python
import flow.describe

# ---- A command -----------------------------------------------------------
resave = flow.describe.Command()
resave.source("cmds/resave.py", "Resave")  # file relative to channel root,
                                            # then the class name inside it.
resave.invoke("mychan", "resave")           # users type .mychan resave …
# resave.prefix(".")                         # default prefix; "$" hides from
                                            # tab completion (used for boot,
                                            # prompt, tip).

# ---- A tool (optional) ---------------------------------------------------
fzf = flow.describe.Tool()
fzf.version("0.56.3")
if bundle := fzf.bundle(platform="win32"):
    bundle.payload("https://github.com/junegunn/fzf/releases/download/v$VERSION/fzf-$VERSION-windows_amd64.zip")
    bundle.bin("fzf.exe")
    bundle.sha1("9dc22afb3a687b10eac57fe27f1a0e4d65c52944")
# $VERSION substitutes the tool.version() string into payload URLs.

# ---- The channel (terminal) ----------------------------------------------
channel = flow.describe.Channel()
channel.parent("unreal.core")    # so unrealcmd, unreal.cmdline, etc. are
                                  # available to this channel's commands.
channel.version("1")              # bump to invalidate the manifest cache
                                  # when the channel changes structurally.
# channel.pip(...)                # DEPRECATED. Do not use. Ship pure-Python
                                  # deps in pylib/; binary deps via Tool().
```

**Mechanics:**
- All module-level Command/Tool/Channel objects are registered just by existing in the module namespace when ushell exec's the describe script.
- Multiple Command objects may share an invoke path across parent channels — the loader builds an MRO from all matching specs. A child class's `main()` can call `super().main()` to run the parent's version. This is how `boot`/`prompt`/`tip` extension works.
- **The file is named `describe.flow.py`** — not `__init__.py`, not `channel.py`. The build system globs for `**/describe.flow.py` to find channels.

Source: `<ushell>/channels/flow/core/system/flow/describe.py` and any of the engine-shipped `describe.flow.py` files for working examples (e.g. `<ushell>/channels/unreal/core/describe.flow.py`).

---

## Authoring a command

Subclass `unrealcmd.Cmd` (UE-context-aware) or `unrealcmd.MultiPlatformCmd` (also injects per-platform SDK env vars). For non-UE commands, subclass `flow.cmd.Cmd` directly.

```python
# cmds/resave.py
import unreal              # for TargetType, Variant, etc.
import unrealcmd           # for Cmd, Arg, Opt
import unreal.cmdline      # for read_ueified (UE arg quoting)
import uelogprinter        # for colorised UE log output

class Resave(unrealcmd.MultiPlatformCmd):
    """Resaves packages under a filesystem folder via the ResavePackages commandlet.

    The commandlet uses -PackageFolder=<filesystem-path>; without it (or
    -Package=<Name> / -Map=<MapName>), ResavePackages resaves EVERY package
    including engine ones. See reference/unreal-args.md §11.
    """

    packagedir = unrealcmd.Arg(str, "Directory of packages to resave (project-relative)")
    extra      = unrealcmd.Arg([str], "Extra args forwarded to the commandlet")
    debug      = unrealcmd.Opt(False, "Use debug editor build")

    def main(self):
        self.use_all_platforms()         # populate SDK env vars
        ue = self.get_unreal_context()

        project = ue.get_project()
        if not project:
            self.print_error("Active project required (use .project <path> first)")
            return False

        target  = ue.get_target_by_type(unreal.TargetType.EDITOR)
        variant = unreal.Variant.DEBUG if self.args.debug else unreal.Variant.DEVELOPMENT
        build   = target.get_build(variant=variant)
        if not build:
            self.print_error(f"No {variant.name.lower()} editor build (run .build editor first)")
            return False

        binary = str(build.get_binary_path())
        if not binary.endswith("-Cmd.exe"):
            # Commandlets need stdout; -Cmd.exe is the console variant.
            binary = binary.replace(".exe", "-Cmd.exe")

        args = (
            project.get_path(),
            "-run=ResavePackages",
            "-PackageFolder=" + self.args.packagedir,  # filesystem path, NOT /Game/...
            "-unattended",
            "-stdout",
            *unreal.cmdline.read_ueified(*self.args.extra),
        )

        cmd = self.get_exec_context().create_runnable(binary, *args)
        if not self.is_interactive():
            cmd.run()
        else:
            uelogprinter.Printer().run(cmd)
        return cmd.get_return_code()
```

**Key mechanics:**

- `unrealcmd.Arg(type_or_default, "description")` — required if a type is given (`Arg(str, "...")`), optional with a default (`Arg("default", "...")`). `[str]` means many-arg (zero-or-more positionals).
- `unrealcmd.Opt(default, "description")` — `--name` flag. Booleans are `Opt(False, ...)`; valued opts need a default that's not a bool.
- `complete_<argname>(self, prefix)` — generator that yields completion candidates for the `<argname>` positional. Already provided for `platform` and `variant` on `unrealcmd.Cmd`.
- `self.args.<name>` — parsed value.
- `self.args.<name> = value` — write-back, marks as "non-default" (affects env-var override).
- `self.get_unreal_context()` — returns `unreal.Context` with `get_project()`, `get_engine()`, `get_target_by_type()`, `get_target_by_name()`, `get_branch()`, `get_config()`, `get_platform_provider()`, `glob()`.
- `self.get_exec_context()` — returns env-aware launcher. `create_runnable(binary, *args)` builds a `Runnable`. `.run()` to wait; `.run2()` to capture stdout.
- Return an int exit code, a bool (True=0, False=1), or use `@flow.cmd.Cmd.summarise` decorator on `main` to auto-print "Result: Success / Failed" + elapsed time (and add `--nosummary`).

**Forbidden positional Arg types:** `bool` (use `Opt`), raw `tuple` (use `[str]` many-arg).

**Don't bypass `unreal.cmdline.read_ueified()`** when forwarding args that contain `-Foo="path with spaces"` — UE's quoting differs from POSIX/Windows shells, and plain subprocess argv will mangle it.

---

## Driving a commandlet from your channel

Two patterns for invoking a commandlet:

### Pattern A — delegate to `_run commandlet` (simplest)

This is what `.cook --attach` does (in `<ushell>/channels/unreal/core/cmds/cook.py:78-94`). It costs an extra child process but inherits `--attach` + log-printing semantics:

```python
import subprocess
args = ("_run", "commandlet", "ResavePackages",
        "--",
        "-PackageFolder=" + self.args.dir,  # filesystem path
        *unreal.cmdline.read_ueified(*self.args.extra))
return subprocess.run(args).returncode
```

The `_run` prefix targets ushell's internal invocation of `.run commandlet`. Same for `_build`, `_cook`, `_uat`, `_p4`.

### Pattern B — launch the editor directly (faster, more control)

What `.cook` itself does (`cmds/cook.py:96-122`) and what the Resave example above shows. Resolve the editor binary, swap `.exe → -Cmd.exe`, prepend `<uproject>` and `-run=<Name>`, then `create_runnable` + `run`.

The trade-off: pattern A gets `--attach` debugger support and the canonical pretty-printer flow for free. Pattern B is faster (no subprocess hop) but you have to wire up debugger plumbing yourself if you want it.

**Use Pattern A by default.** Only fall to Pattern B when:
- You need to manipulate the command line in ways `_run commandlet` doesn't expose.
- You want to avoid the subprocess overhead for a frequently-invoked commandlet.

---

## Driving UAT from your channel

Use the `_uat` internal shim:

```python
import subprocess
args = ("_uat", "BuildCookRun",
        "--",
        "-project=" + str(project.get_path()),
        "-platform=Win64",
        "-clientconfig=Development",
        "-build", "-cook", "-stage", "-pak", "-iostore", "-compressed")
return subprocess.run(args).returncode
```

The `_uat` shim does the same env setup as `.uat` (builds UAT, injects `-ScriptsForProject=`, etc.). **Do not call `RunUAT.bat` directly from a channel** — you'd duplicate that plumbing.

For BuildGraph from a channel:

```python
subprocess.run(("_uat", "BuildGraph", "--",
                "-script=" + script_xml_path,
                "-target=" + target_node))
```

---

## Deps & distribution

### Pure-Python deps

Drop them in `channels/<name>/pylib/<package>/` and they're auto-importable. ushell uses this for its own internal libs (`unrealcmd`, `unreal.*`, `uelogprinter`, `peafour`, `p4utils`, `zen.*`, `fzf`, etc.).

```
channels/mychan/
  pylib/
    mychan/
      __init__.py            # this IS an __init__.py - regular Python package
      helpers.py             # `from mychan.helpers import ...` from your cmds
```

### Binary deps via `Tool()`

```python
fzf = flow.describe.Tool()
fzf.version("0.56.3")
fzf.source("https://github.com/junegunn/fzf/releases/latest", r"fzf-(\d+\.\d+\.\d+)-")
if bundle := fzf.bundle(platform="win32"):
    bundle.payload("https://github.com/junegunn/fzf/releases/download/v$VERSION/fzf-$VERSION-windows_amd64.zip")
    bundle.bin("fzf.exe")
    bundle.sha1("9dc22afb3a687b10eac57fe27f1a0e4d65c52944")
if bundle := fzf.bundle(platform="linux"):
    bundle.payload("https://github.com/junegunn/fzf/releases/download/v$VERSION/fzf-$VERSION-linux_amd64.tar.gz")
    bundle.bin("fzf")
    bundle.sha1("e8cc2ff14b0a39d1ba0c87e8f350557dcc56ac51")
```

ushell downloads, verifies the sha1, extracts, and exposes `bin` paths via shims on the session `PATH`.

### Pips: deprecated

`Channel.pip(name)` exists but the docstring is explicit: *"Please do not use! Pips come with security and licensing headaches so support for them has been removed."* Vendor pure-Python deps under `pylib/`; use `Tool()` for native binaries.

### Site-level install paths

- **Per-user:** `$USERPROFILE/.ushell/channels/<name>/` — discovered by ushell at boot.
- **Per-branch:** `<branch>/Engine/Platforms/<X>/Extras/ushell/platform_*.py` — only for platform-plugin channels (extending `unreal._platform.Platform`).
- **Standalone bundle:** `.ushell gather <destdir>` (the existing ushell command) produces a deployable bundle. Useful for UGS, which can deploy ushell + your channels to teammates regardless of branch.

---

## Boot / prompt / tip hooks

Register a `boot`/`prompt`/`tip` command with `prefix("$")` to chain into the framework's:

```python
# channels/mychan/describe.flow.py
my_boot = flow.describe.Command()
my_boot.source("boot.py", "Boot")
my_boot.invoke("boot")
my_boot.prefix("$")
```

```python
# channels/mychan/boot.py
import flow.cmd

class Boot(flow.cmd.Cmd):
    def run(self, env):
        # Set per-session env vars, run startup logic, etc.
        env["MYCHAN_INITIALIZED"] = "1"
        return super().run(env)
```

The MRO walks parent-channels-first, so a child class's `run(env)` / `prompt(context)` / `get_tips()` overrides cleanly via `super()`. See `<ushell>/channels/unreal/core/{boot,prompt,tips}.py` for working examples.

---

## Smallest viable channel template

Copy-pasteable. Creates a `.mychan hello` command that prints the active project name.

```python
# channels/mychan/describe.flow.py
import flow.describe
hello = flow.describe.Command()
hello.source("cmds/hello.py", "Hello")
hello.invoke("mychan", "hello")
channel = flow.describe.Channel()
channel.parent("unreal.core")
channel.version("1")
```

```python
# channels/mychan/cmds/hello.py
import unrealcmd
class Hello(unrealcmd.Cmd):
    """Says hello and prints the active project."""
    name = unrealcmd.Arg("world", "Who to greet")
    def main(self):
        ue = self.get_unreal_context()
        project_name = ue.get_project().get_name() if ue.get_project() else "(no project)"
        print(f"Hello {self.args.name} — active project is {project_name}")
        return 0
```

**Install for personal use:** drop into `$USERPROFILE/.ushell/channels/mychan/`. **Install per-branch:** drop into the branch's ushell `channels/` directory. **Install for sharing via UGS:** add to the gathered `.ushell.zip`.

**Smoke test:**

```
cmd.exe /d /s /c "call <ushell.bat> --project=<uproject> && .mychan hello Aaron"
```

Expected output: `Hello Aaron — active project is MyProject`.

If `.mychan hello` isn't recognised:
- Check the channel directory is under one of the discovery paths.
- Check `describe.flow.py` parses without errors (run `python <describe.flow.py>` to syntax-check).
- Bump `channel.version("2")` to invalidate the manifest cache, then retry.
