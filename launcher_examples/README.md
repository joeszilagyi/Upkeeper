# Launcher Examples

These scripts are tracked examples for running Upkeeper loops from a normal
terminal. They are intentionally small wrappers around `./Upkeeper` or a
repo-local `UPKEEPER_CMD`; durable behavior belongs in the central `Upkeeper`
file, not in a launcher.

Validate examples before publishing changes:

```sh
bash -n launcher_examples/*.sh
launcher_examples/spark_5.3_burn_out_xhigh.sh --help
UPKEEPER_LOOP_DRY_RUN=1 launcher_examples/spark_5.3_burn_out_xhigh.sh
```

## Included

- `spark_5.3_burn_out_xhigh.sh`: a plain Spark-5.3 xhigh loop that sleeps after
  successful cycles and stops on the first non-zero Upkeeper exit.
