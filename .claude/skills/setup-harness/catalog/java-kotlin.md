# Java/Kotlin

## Signals
Kind: stack
Manifest: build.gradle, build.gradle.kts, pom.xml
Lockfile: gradle.lockfile
Workspace: settings.gradle `include`, settings.gradle.kts `include`, pom.xml `<modules>`
Extensions: .java .kt .kts
Shebangs: None.
Runtime version: .java-version, .sdkmanrc, .tool-versions, mise.toml, the build's toolchain block

## lint

### ktlint
Publisher: ktlint
Tier: 2: https://github.com/pinterest/ktlint
Evidence: `.editorconfig` `ktlint_*` keys, `ktlint` in the build or CI
Rung: edit
Files: .kt .kts
Run: `ktlint {files}`
Hook: local
Pin: package maven com.pinterest.ktlint:ktlint-cli
Route: `mkdir -p "$HOME/.local/lib" "$HOME/.local/bin" && curl -fsSLo "$HOME/.local/lib/ktlint-{version}.jar" https://repo1.maven.org/maven2/com/pinterest/ktlint/ktlint-cli/{version}/ktlint-cli-{version}-all.jar && printf '#!/bin/sh\nexec java -jar "%s" "$@"\n' "$HOME/.local/lib/ktlint-{version}.jar" > "$HOME/.local/bin/ktlint" && chmod +x "$HOME/.local/bin/ktlint"`; Blocked: release binaries
Constraints: Kotlin files only; Java has no vendor linter, so a Java-only member takes no lint default. Needs a JVM, which the image carries (OpenJDK 21). The route puts the Maven Central jar behind a `ktlint` launcher in `~/.local/bin`, so the hook entry names the tool's own binary.
Traps: 2.0 moves to the `io.github.ktlint` group; the pin stays on `com.pinterest.ktlint` through 1.x.

## format

### google-java-format
Publisher: Google
Tier: 2: https://github.com/google/google-java-format
Evidence: `google-java-format` in the build (Spotless `googleJavaFormat()`) or CI
Rung: edit
Files: .java
Run: `google-java-format --replace {files}`
Hook: local
Pin: package maven com.google.googlejavaformat:google-java-format
Route: `mkdir -p "$HOME/.local/lib" "$HOME/.local/bin" && curl -fsSLo "$HOME/.local/lib/google-java-format-{version}.jar" https://repo1.maven.org/maven2/com/google/googlejavaformat/google-java-format/{version}/google-java-format-{version}-all-deps.jar && printf '#!/bin/sh\nexec java -jar "%s" "$@"\n' "$HOME/.local/lib/google-java-format-{version}.jar" > "$HOME/.local/bin/google-java-format" && chmod +x "$HOME/.local/bin/google-java-format"`; Blocked: release binaries
Constraints: Java files only, beside ktlint's Kotlin, so both defaults are wired, each hook scoped by `types`. Needs JDK 21 or later. The route puts the jar behind a launcher, as ktlint's does.
Traps: a repo formatting through Spotless keeps Spotless, wired through its own `spotlessApply` task; its `ratchetFrom 'origin/main'` fails on a shallow clone until `git fetch origin main`.

### ktlint format
Publisher: ktlint
Tier: 2: https://github.com/pinterest/ktlint
Evidence: `ktlint` evidence, as above
Rung: edit
Files: .kt .kts
Run: `ktlint --format {files}`
Hook: local
Pin: package maven com.pinterest.ktlint:ktlint-cli
Route: `mkdir -p "$HOME/.local/lib" "$HOME/.local/bin" && curl -fsSLo "$HOME/.local/lib/ktlint-{version}.jar" https://repo1.maven.org/maven2/com/pinterest/ktlint/ktlint-cli/{version}/ktlint-cli-{version}-all.jar && printf '#!/bin/sh\nexec java -jar "%s" "$@"\n' "$HOME/.local/lib/ktlint-{version}.jar" > "$HOME/.local/bin/ktlint" && chmod +x "$HOME/.local/bin/ktlint"`; Blocked: release binaries
Constraints: Kotlin files only, beside google-java-format's Java; one ktlint pin serves both roles.
Traps: None.

## typecheck

### gradle classes
Publisher: Gradle
Tier: 2: https://docs.gradle.org/current/userguide/java_plugin.html
Evidence: `build.gradle`, `build.gradle.kts`
Rung: turn
Run: `gradle classes`
Hook: local
Pin: None.
Route: None.
Constraints: the image's preinstalled `gradle`, never `./gradlew`: every `services.gradle.org` distribution the wrapper downloads redirects to a GitHub release asset, which the cloud refuses. Plugins and dependencies come from the Gradle plugin portal and Maven Central, which pass. A project is the smallest unit it takes.
Traps: the preinstalled Gradle's version is the image's, not the wrapper's `distributionUrl`, so a build needing a newer Gradle fails; noble's apt `gradle` is 4.4.1 and no fix. The first run starts a daemon and pays every compile (13.6 s cold, 0.9 s warm on a toy, measured).

### maven compile
Publisher: Apache Maven
Tier: 2: https://maven.apache.org/plugins/maven-compiler-plugin/
Evidence: `pom.xml`
Rung: turn
Run: `mvn -q compile`
Hook: local
Pin: None.
Route: None.
Constraints: the image's preinstalled `mvn`; a repo's `./mvnw` also works, its distribution coming from Maven Central.
Traps: None.

## test runner

### gradle test
Publisher: Gradle
Tier: 2: https://docs.gradle.org/current/userguide/java_testing.html
Evidence: `src/test/` in a Gradle project
Rung: turn
Run: `gradle test`
Hook: local
Pin: None.
Route: None.
Constraints: the preinstalled `gradle`, as for `gradle classes`.
Traps: None.

### maven test
Publisher: Apache Maven
Tier: 2: https://maven.apache.org/surefire/maven-surefire-plugin/
Evidence: `src/test/` in a Maven project
Rung: turn
Run: `mvn -q test`
Hook: local
Pin: None.
Route: None.
Constraints: the preinstalled `mvn`.
Traps: None.

## affected tests

### gradle up-to-date test
Publisher: Gradle
Tier: 2: https://docs.gradle.org/current/userguide/incremental_build.html
Evidence: a Gradle project
Rung: turn
Run: `gradle test`
Hook: local
Pin: None.
Route: None.
Constraints: native and exact at module level, no git: a test task whose input fingerprints did not change is up to date and skipped, so the member's test command is its affected-test command.
Traps: Develocity's Predictive Test Selection is a commercial server, not a default.

### maven also-make-dependents
Publisher: Apache Maven
Tier: 2: https://maven.apache.org/guides/mini/guide-multiple-modules.html
Evidence: a Maven project
Rung: turn
Run: `mvn -q -pl {member} -amd test`
Hook: local
Pin: None.
Route: None.
Constraints: Maven skips no up-to-date tests and `-Dtest=` filters by name only, so the row runs the member's module and every module depending on it (`-amd`, its reverse dependents). A reactor started inside the module cannot see its dependents, so this command runs from the stack root, `{member}` the module's path relative to it (`-f <root>/pom.xml` from the member's directory).
Traps: None.

## language server

### jdtls
Publisher: Eclipse
Tier: 2: https://github.com/eclipse-jdtls/eclipse.jdt.ls
Evidence: `.claude/skills/harness-jdtls-lsp/`, `jdtls-lsp@claude-plugins-official` in `.claude/settings.json` `enabledPlugins`
Rung: None.
Run: `jdtls`
Hook: None.
Pin: None.
Route: None.
Constraints: the Anthropic `jdtls-lsp` plugin launches a `jdtls` from `PATH`, which needs Java 21 and python3.
Unavailable: no registry route: jdtls ships only as a `download.eclipse.org` tarball whose name carries a build timestamp, on no registry the version rule reads, and the plugin's `jdtls` would be a binary from `PATH` the harness neither installs nor pins.
Local-only: cloud sessions start no plugin language server.
Traps: None.

### kotlin-lsp
Publisher: JetBrains
Tier: 2: https://github.com/Kotlin/kotlin-lsp
Evidence: `.claude/skills/harness-kotlin-lsp/`, `kotlin-lsp@claude-plugins-official` in `.claude/settings.json` `enabledPlugins`
Rung: None.
Run: `kotlin-lsp --stdio`
Hook: None.
Pin: None.
Route: None.
Constraints: Alpha and partially closed-source.
Unavailable: no Linux route: it downloads only from `download.jetbrains.com`, and the plugin's Homebrew formula is macOS-only.
Local-only: cloud sessions start no plugin language server.
Traps: None.
