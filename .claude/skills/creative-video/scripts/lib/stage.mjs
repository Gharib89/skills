// A stage's top-level catch: whatever escapes the entry point, a loader's
// refusal or a helper's throw, prints one `<name>: <message>` line on stderr
// and exits 1, never a stack. Call it first in each command-line entry point.
export function stage(name) {
  const refuse = (e) => {
    console.error(`${name}: ${e instanceof Error ? e.message : e}`);
    process.exit(1);
  };
  process.on("uncaughtException", refuse);
  process.on("unhandledRejection", refuse);
}
