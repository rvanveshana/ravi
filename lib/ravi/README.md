# The `ravi` source package

| Source | Purpose |
| --- | --- |
| [core.rk](core.rk) | Identity and none-check helpers |
| [math.rk](math.rk) | Arithmetic, absolute value, min/max, clamp, and integer GCD |
| [collections.rk](collections.rk) | Sum and short-circuit all/any predicates |
| [exceptions.rk](exceptions.rk) | Experimental named exception facades |
| [json.rk](json.rk) | Bounded JSON encoding and parsing |
| [files.rk](files.rk), [paths.rk](paths.rk) | UTF-8 text files and platform paths |
| [bytes.rk](bytes.rk), [time.rk](time.rk) | UTF-8 byte conversion and clock/timer helpers |
| [tasks.rk](tasks.rk), [channels.rk](channels.rk) | Task lifecycle and bounded communication |
| [logging.rk](logging.rk), [testing.rk](testing.rk), [environment.rk](environment.rk) | Diagnostics, assertions, environment lookup |
| [network.rk](network.rk) | Networking blueprint |
| [kirana.rk](kirana.rk) | UI blueprint |

The [standard-library reference](../../docs/user_docs/standard-library.md) owns
public API descriptions and limitations. The [contributor guide](../../docs/contributing.md)
owns implementation and documentation requirements.
See [runtime contracts](../../docs/task-runtime.md) for ownership and resource limits.
