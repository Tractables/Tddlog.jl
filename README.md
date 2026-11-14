# Tddlog.jl

Exact probabilistic inference from Julia with
[tddlog](https://github.com/Tractables/tddlog). tddlog computes exact
probabilities for ProbLog programs, LPADs, Dice programs, Circulette netlists
and Bayesian and Markov networks, by compiling them bottom-up into tree
decision diagrams. This package calls tddlog's C library in process.

## Install

```julia
import Pkg
Pkg.add(url = "https://github.com/Tractables/Tddlog.jl")
```

`Pkg.add` downloads the C library of tddlog's release 0.1.1 for Linux
(x86-64 and ARM64, glibc) or macOS (x86-64 and ARM64) as a Julia artifact,
SHA-256 checked. No Rust toolchain and no `tddlog` command are needed. The
package's version is the version of the tddlog release it wraps.

Windows: the release's Windows archive is a `.zip`, which Pkg cannot unpack.
Download `tddlog-c-v0.1.1-x86_64-pc-windows-msvc.zip` from the
[release](https://github.com/Tractables/tddlog/releases/tag/v0.1.1), unpack
it, and set `ENV["TDDLOG_LIBRARY"]` to the path of its `tddlog_c.dll` before
`using Tddlog`. The same variable loads any other build of the library of the
same version.

## Use

```julia
using Tddlog

program = """
0.1::burglary.
0.2::earthquake.
0.7::hears_alarm(john).
0.4::hears_alarm(mary).
alarm :- burglary.
alarm :- earthquake.
calls(X) :- alarm, hears_alarm(X).
evidence(calls(john), true).
query(burglary).
query(calls(mary)).
"""

s = solve(program; evidence_probability = true)
s.answers                # ["burglary" => 0.357..., "calls(mary)" => 0.4]
Dict(s.answers)["calls(mary)"]
s.evidence_probability   # P(e) = 0.196
```

`solve(program; options...)` answers the queries of `program`, given as
text, as the `tddlog` command does for a file holding it. Its keywords are
the command line's options:

| keyword | default | meaning |
| --- | --- | --- |
| `format` | `"problog"` | `"problog"` (an LPAD where it holds `:- begin_lpad.`), `"dice"`, `"circulette"`, or a network's: `"bif"`, `"hugin"`, `"xdsl"`, `"uai"` |
| `evidence` | `nothing` | for a network, the text of its evidence file (Ace `.inst`, or UAI `.evid`) |
| `vtree` | `"auto"` | the vtree strategy, the command's `--vtree` |
| `evidence_probability` | `false` | also compute P(e), the probability of the evidence |
| `queries` | `true` | `false` leaves the queries out, as `--no-queries` does |
| `arguments` | `String[]` | terms that take the places `$1`, `$2`, ... of the program |

It returns a `Solution`:

- `answers`: each query, as ProbLog prints it, paired with its probability,
  in the program's order; `nothing` where the evidence is inconsistent;
- `consistent`: whether the evidence is consistent;
- `evidence_probability` and `log10_evidence_probability`: P(e) and its
  base-10 logarithm, which is exact beyond a `Float64`'s range; `nothing`
  unless asked for.

A program tddlog cannot answer raises a `Tddlog.Error`: a
`Tddlog.ParseError`, `Tddlog.GroundingError` or `Tddlog.CompilationError`,
with the message the command line prints. Options that break the library's
contract, such as an unknown format, raise an `ArgumentError`, and an unknown
keyword a `MethodError`. `Tddlog.version()` is the version of the library
loaded.

tddlog is single-threaded; Julia threads may each solve their own program.
The [guide](https://tractables.github.io/tddlog/guide/) describes the
languages tddlog reads.

## Tests

```julia
import Pkg
Pkg.test("Tddlog")
```

The tests check the answers of small programs against probabilities computed
by hand. With `ENV["TDDLOG_COMMAND"]` set to a `tddlog` command of the same
release, they also check that `solve` gives the command's answers bit for
bit.

## License

Apache License 2.0, as tddlog.
