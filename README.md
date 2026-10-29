# cmake-conan

[![Build](https://github.com/tnt-music-studios/cmake-conan/actions/workflows/cmake_conan.yml/badge.svg)](https://github.com/tnt-music-studios/cmake-conan/actions/workflows/cmake_conan.yml)

CMake dependency provider for the Conan C and C++ package manager.

> [!IMPORTANT]
> **On Windows, it is recommended to add the Conan cache directory to your antivirus exclusion list.**
>
> When cmake-conan runs during CMake configuration, Conan writes package files to its local cache. Windows Defender (and other real-time antivirus software) may scan these files as they are written, creating a race condition where Conan attempts to read the files before the scan completes. This causes intermittent `FileNotFoundError` failures during the export step of `conan create` or `conan install`.
>
> A common symptom is a build that **fails on the first run but succeeds on the second** without any changes.
>
> **To fix this, exclude the Conan cache directory from real-time scanning:**
>
> 1. Open **Windows Security** (search "Windows Security" in the Start menu)
> 2. Go to **Virus & threat protection** > **Virus & threat protection settings** > **Manage settings**
> 3. Scroll to **Exclusions** > **Add or remove exclusions**
> 4. Click **Add an exclusion** > **Folder**
> 5. Select your Conan cache directory (default: `C:\Users\<username>\.conan2\`, or the [`CONAN_HOME`](#pinning-the-conan-home-per-build-tree) a build tree pins)
>
> You can find your cache location by running `conan config home`.

## Quickstart

Prerequisites:
* CMake 3.24
* Conan 2.0.5
* Git (the provider requires it at configure time)
* A CMake-based project that contains a `conanfile.txt` or `conanfile.py` to list the required dependencies.

First, clone this repository

```bash
git clone https://github.com/tnt-music-studios/cmake-conan.git
```

### Example project

This repository contains a `CMakeLists.txt` with an example project that depends on `fmt`. 

```bash
cd cmake-conan/example
mkdir build
cmake -B build -S . -DCMAKE_PROJECT_TOP_LEVEL_INCLUDES=../conan_provider.cmake -DCMAKE_BUILD_TYPE=Release
cmake --build build --config Release
```

### In your own project

* Ensure you have placed a `conanfile.txt` or `conanfile.py` at the root of your project, listing your requirements. You can see [conanfile.txt](example/conanfile.txt) for an example, or check the Conan documentation for `conanfile`: [.txt docs](https://docs.conan.io/2/reference/conanfile_txt.html), [.py docs](https://docs.conan.io/2/reference/conanfile/attributes.html#requirements).

* When first invoking CMake to configure the project, pass `-DCMAKE_PROJECT_TOP_LEVEL_INCLUDES=[path-to-cmake-conan]/conan_provider.cmake`. This will ensure that `conan install` is invoked from within CMake. This integration **does not require making any changes to your `CMakeLists.txt` scripts**.

* When `CONAN_HOST_PROFILE` contains `auto-cmake` (the default), host profile detection is deferred until after compilers are configured, so the generated `${CMAKE_BINARY_DIR}/conan_host_profile` is available even for projects that have no Conan dependencies (where `find_package()` is never called).

## Using a local recipes index

If a project contains a top-level `conan-recipes/` checkout, cmake-conan can consume recipes from
it automatically before running `conan install`. The intended shared checkout for TNT Music
Studios projects is
[`tnt-music-studios/conan-recipes`](https://github.com/tnt-music-studios/conan-recipes), but any
checkout with Conan's `local-recipes-index` layout works. That layout is the same high-level shape
used by ConanCenter:

```text
my-project/
  CMakePresets.json
  conanfile.txt
  conan-recipes/
    recipes/
      libebur128/
        config.yml
        all/
          conanfile.py
          conandata.yml
          test_package/
```

With that directory present, no extra `CMAKE_PROJECT_TOP_LEVEL_INCLUDES` wrapper is needed. Continue
pointing CMake at `conan_provider.cmake` as usual. On the first dependency resolution,
cmake-conan registers `${CMAKE_SOURCE_DIR}/conan-recipes` as a recipes-only
`local-recipes-index` remote at the highest priority (index 0), then proceeds with the normal
`#recipe:` handling and `conan install` flow. The remote is written to the active Conan home's
remote list and stays there; later configures overwrite it in place.

For a project that uses Git submodules, add the shared recipes checkout at the repository root:

```bash
git submodule add https://github.com/tnt-music-studios/conan-recipes.git conan-recipes
```

For a regular checkout, clone it to the same top-level path:

```bash
git clone https://github.com/tnt-music-studios/conan-recipes.git conan-recipes
```

For example, a project can declare an unpublished recipe normally:

```ini
[requires]
libebur128/1.2.6

[generators]
CMakeDeps
```

If the matching binary package is already in the active Conan cache, Conan reuses it. If it is
missing and `CONAN_INSTALL_ARGS` includes `--build=missing`, Conan builds the binary from the local
recipe and stores it in the same cache used by the rest of the dependency graph.

cmake-conan restricts the local recipes remote to package folders that contain `config.yml`. For a
checkout containing `recipes/libebur128/config.yml`, the generated allowed package pattern is
`libebur128/*`. Additional package folders produce additional allowed package patterns. If the
index has no `recipes/` folder, nothing is registered; if no package folder holds a `config.yml`,
cmake-conan reports that and registers nothing.

This feature is independent of `#recipe:` annotations. Use a local recipes index for
ConanCenter-style recipe folders, and keep using `#recipe:` annotations for standalone Git
repositories that should be cloned and built with `conan create`.

The default settings are:

```cmake
CONAN_LOCAL_RECIPES_AUTO_REGISTER=TRUE
CONAN_LOCAL_RECIPES_INDEX=${CMAKE_SOURCE_DIR}/conan-recipes
CONAN_LOCAL_RECIPES_REMOTE_NAME=local_conan_recipes
```

Set `CONAN_LOCAL_RECIPES_INDEX` when the recipes checkout lives somewhere else, set
`CONAN_LOCAL_RECIPES_REMOTE_NAME` when the generated Conan remote needs a project-specific name, or
set `CONAN_LOCAL_RECIPES_AUTO_REGISTER=FALSE` to disable the behavior.

## Building package recipes from Git

***Package not found on conancenter or any configured remote? Not even in your local cache!? cmake-conan has you covered!***

When a required package can't be found in any configured Conan remote or your local cache, cmake-conan can automatically fetch the recipe from a Git repository and build it from source. This is useful for private packages or packages not yet published to a remote.

To enable this feature, add a `#recipe:` comment after the requirement specifying the Git repository URL:

**conanfile.py:**
```python
def requirements(self):
    self.requires("mypackage/1.2.3")  #recipe: https://github.com/user/mypackage.git
    self.requires("private/2.0.0@myuser/stable")  #recipe: https://github.com/org/private.git
```

**conanfile.txt:**
```ini
[requires]
mypackage/1.2.3  #recipe: https://github.com/user/mypackage.git
private/2.0.0@myuser/stable  #recipe: https://github.com/org/private.git
```

The annotation must sit on the same line as the requirement, and only regular requirements are read: `self.requires(...)` calls in `conanfile.py` and lines of the `[requires]` section of `conanfile.txt`. In `conanfile.py`, the reference must be the call's first argument, as a string literal in single or double quotes; further arguments may follow. Commented-out lines are skipped. Any other annotation draws a warning and its requirement is resolved as usual: one on a tool requirement (`conan create` would build it for the host rather than the build context), a reference built at runtime, or a URL that does not end in `.git`.

Annotated dependencies are resolved recursively. If a recipe created from Git declares its own `#recipe:`-annotated requirements, cmake-conan will create those transitive dependencies first before running `conan create` for the parent package.

The recipe URL can point to any Git clone target that ends in `.git`, including `https://`, SSH, or local `file://` URLs. The repository must hold the recipe's `conanfile.py` at its root. It is queried with `git ls-remote` on every configure that runs `conan install`, so it must be reachable even when the package is already cached or published.

When cmake-conan encounters a package with a `#recipe:` annotation, it performs the following checks:

1. **Remote check:** If the package exists on a configured Conan remote, it is used directly (no build required).
2. **Cache + tag check:** If the package exists in the local cache and the version resolves to a Git tag, the cached package is used (tags are treated as [immutable](#tag-immutability)).
3. **Cache + branch check:** If the package exists in the local cache but the version resolves to a Git branch, cmake-conan compares the commit of the recipe clone this build tree kept (under `${CMAKE_BINARY_DIR}/conan/_recipes/<name>`) with the branch's remote head. The cached package is removed and rebuilt if the branch has new commits, or if this build tree has no clone to compare.
4. **Build from source:** If none of the above conditions are met, cmake-conan shallow-clones the repository (with submodules) at the appropriate tag/branch, runs `conan create`, and continues with `conan install`.

`conan create` receives the same host and build profiles as `conan install`, plus `CONAN_INSTALL_ARGS`. Its `build_type` is `CMAKE_BUILD_TYPE`, or `Release` with a multi-configuration generator. The package's `test_package` step is skipped.

### Version Resolution: Tags vs Branches

The Git branch/tag to create the package from is derived from the package version in the `requires` statement. Versions starting with a number are assumed to be semver strings and get a `v` prefix:

| Version | Derived Git Ref |
|---------|-----------------|
| `1.2.3` | `v1.2.3` |
| `develop` | `develop` |

The derived Git ref is checked against the repository for a matching tag first, then for a matching branch.

**Tags:** Tags are assumed to be [immutable](#tag-immutability), making them the preferred method for minimizing build times and ensuring reproducible builds.

**Branches:** Branches are useful during active development when you want to consume a package without tagging an untested version. However, because branches are mutable, cmake-conan checks for new remote commits on each build and rebuilds the package when changes are detected.

If the derived Git ref matches no tag or branch, configuration aborts when the package has to be built, because the clone fails. If a package with that reference is already cached, cmake-conan uses it with a warning that its integrity cannot be verified.

### Tag Immutability

> [!CAUTION]
> **Tags are assumed to be immutable.** Be cautious when moving tags in Git. Moving tags is considered bad practice and will not trigger a rebuild if a package with the same version is already in the cache. If this happens, you must manually remove the package from the cache with `conan remove <package_ref>` to force a rebuild.

## Known limitations with Conan 2.0

* Only the `CMakeDeps` generator is specified - for build settings that would otherwise be provided by `CMakeToolchain` (for example, the compiler itself or other global build settings) please invoke Conan separately as per [documentation](https://docs.conan.io/2/tutorial/consuming_packages/build_simple_cmake_project.html).
* Currently this only works such that Conan can satisfy invocations to CMake's `find_package`. For dependencies that have logic outside of `find_package`, for example, by making direct calls to `find_program`, `find_library`, `find_path` or `find_file`, these may not work correctly.
* When using a single-configuration CMake generator, you must specify a valid `CMAKE_BUILD_TYPE` (can't be left blank). Alternatively, `CONAN_INSTALL_BUILD_CONFIGURATIONS` can be set to a non-empty list of build types (see next section).
* Deriving Conan settings is currently only supported on the most common platforms with the most popular compilers.

## Pinning the Conan home per build tree
`-DCONAN_HOME=<absolute path>` pins the Conan home (its cache and config) for that build tree. The provider exports it as the `CONAN_HOME` environment variable of every Conan call, overriding any `CONAN_HOME` already in the environment, and does so again on the re-runs of CMake a build tool triggers on its own, which carry none of a preset's environment. Conan still reads a `.conanrc` file found in or above the working directory before the environment, so a `.conanrc` outranks this setting. Left empty (the default), Conan resolves its home as usual: a `.conanrc` file, then the `CONAN_HOME` environment variable, then `~/.conan2`. Because it is a cache variable, a wrapper included before `conan_provider.cmake` can give it a project default.

## Customizing Conan profiles
The CMake-Conan dependency provider will create a Conan profile where the settings (`os`, `arch`, `compiler`, `build_type`) are retrieved from what CMake has detected for the current build. Conan uses two profiles for dependencies, the _host_ and the _build_ profiles. You can read more about them [here](https://docs.conan.io/2.0/tutorial/consuming_packages/cross_building_with_conan.html?highlight=build%20profile#conan-two-profiles-model-build-and-host-profiles). In CMake-Conan, the default behaviour is as follows:

* Conan host profile: settings detected from CMake. For anything that cannot be detected from CMake, it falls back to the `default` Conan profile.
* Conan build profile: the `default` Conan profile.

Please note that for the above to work, a `default` profile must already exist. If it doesn't, `cmake-conan` will invoke Conan's autodetection mechanism which tries to guess the system defaults.

If you need to customize the profile, you can do so by modifying the value of `CONAN_HOST_PROFILE` and `CONAN_BUILD_PROFILE` and passing them as CMake cache variables. Some examples:

* `-DCONAN_HOST_PROFILE="default;auto-cmake"`: perform autodetection as described above, and fallback to the default profile for anything else (default behaviour).
* `-DCONAN_HOST_PROFILE=clang16`: do not perform autodetection, and use the `clang16` profile which must exist in the Conan profiles folder (see [docs](https://docs.conan.io/2.0/reference/commands/profile.html?highlight=profiles%20folder#conan-profile-list).)
* `-DCONAN_BUILD_PROFILE="/path/to/profile"`: alternatively, provide a path to a profile file that may be anywhere in the filesystem.
* `-DCONAN_HOST_PROFILE="default;custom"`: semi-colon separated list of profiles. A compound profile will be used (see [docs](https://docs.conan.io/2.0/reference/commands/install.html#profiles-settings-options-conf)) - compunded from left to right, where right has the highest priority.

Any `build_type` specified by a host profile is ignored.
The `build_type` is handled separately, and the default behavior depends on the CMake generator used:
* For single-configuration generators, `conan install` is executed once with `build_type` set to the `CMAKE_BUILD_TYPE`. The `CMAKE_BUILD_TYPE` must not be empty.
* For multi-configuration generators, `conan install` is executed twice: once with `build_type` set to `Release`, and a second time with `build_type` set to `Debug`.

You can override the default build type(s) by setting the `CONAN_INSTALL_BUILD_CONFIGURATIONS` CMake variable to a list of build types.
`conan install` will then be invoked once for each build type.
This can be used with both single- and multi-configuration generators, although currently only one build type can be specified for single-configuration generators.
For example:
* `-DCONAN_INSTALL_BUILD_CONFIGURATIONS=Release;Debug`: execute `conan install` for both `Release` and `Debug` build types with a multi-configuration generator.
* `-DCONAN_INSTALL_BUILD_CONFIGURATIONS=Release`: execute `conan install` once for just the `Release` build type, applicable for both single- and multi-configuration generators.

## Customizing the invocation of Conan install
The CMake-Conan dependency provider will autodetect and pass the profile information as described above. If the `conan install` command invocation needs to be customized further, the `CONAN_INSTALL_ARGS` variable can be used. 
* By default, `CONAN_INSTALL_ARGS` is initialised to pass `--build=missing`. If you customize this variable, please be aware that Conan will revert to its default behaviour unless you specify the `--build` flag.
* `CONAN_INSTALL_ARGS` is also passed to the `conan create` calls that build [`#recipe:` packages](#building-package-recipes-from-git).
* Some arguments are reserved for the dependency provider implementation and must not be set in `CONAN_INSTALL_ARGS`:
  * The path to a `conanfile.txt|.py`.
  * The output folder (`-of`), which is `${CMAKE_BINARY_DIR}/conan`.
  * The output format (`--format`).
  * The build type setting (`-s build_type=...`).
* Values are semi-colon separated, e.g. `--build=never;--update;--lockfile-out=''`

## Development, contributors

There are some tests, you can run in python, with pytest, for example:

```bash
$ pytest -rA
```
