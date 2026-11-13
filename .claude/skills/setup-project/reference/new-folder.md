# New folder: the `repo-and-remote` step

SKILL.md loads this when the `repo-and-remote` row names a missing piece, from
its step 5 or, for the stack table, its step 3. "Step 4" below is SKILL.md's.

**`repo-and-remote`**: act on each missing piece the row's evidence names, on
its own, in this order, then commit:
1. **`no .git`**: `git init -b main`, which keeps the files already there.
2. **`no origin remote`**: create the remote from the interview, on GitHub
   only:

   ```sh
   gh repo create <name> --<visibility> --description '<summary>' --source . --remote origin
   ```

   `<name>` is the answer, its `<org>/` prefix included; `<visibility>` is the
   answer as given; `<summary>` is the description's first sentence, each `'`
   in it written as `'\''` so the shell passes it as typed. In a repo with
   commits, add `--push`, then run `git remote set-head origin -a`, so its
   history is the base step 4 reads. A project hosted elsewhere is the owner's
   to create: they add its repo as `origin`, and the next run reads it.

   Step 4 runs here, if it has not yet.
3. **`no origin remote`**, continued: write `README.md` (the name as its
   title, the description under it) and `CLAUDE.md` (the name as its title,
   the description as its overview), each only where absent. Create no
   `GLOSSARY.md` or ADR: the domain model grows later.
4. **`no stack manifest`**, that evidence exactly: run the stack's own init,
   after the seeding above (`bun init` writes a `CLAUDE.md` where none
   exists):

   | Stack | Init |
   |---|---|
   | Python | `uv init` |
   | TypeScript or JavaScript | `bun init -y` |
   | Rust | `cargo init` |
   | Go | `go mod init <module>` |
   | .NET | `dotnet new console` |

   `<module>` is the origin URL's host and path, with no scheme, no `git@`, a
   `:` before the path read as `/`, and no `.git`, so an HTTPS and an SSH
   origin both give `github.com/<org>/<name>`. `uv init` writes its
   `.gitignore` only when it creates the git repo itself, so after it, where
   none exists, write `.venv`, `__pycache__/`, `*.py[oc]`, `build/`, `dist/`,
   `wheels/` and `*.egg-info`, one per line. Any other stack: ask the owner
   for its init command and run that; never pick one.

An origin that is neither GitHub nor Azure DevOps is the owner's to repoint:
print it and stop.
