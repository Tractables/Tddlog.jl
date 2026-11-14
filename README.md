# Tddlog.jl

Exact probabilistic inference from Julia with
[tddlog](https://github.com/Tractables/tddlog). tddlog computes exact
probabilities for ProbLog programs, LPADs, Dice programs, Circulette netlists
and Bayesian and Markov networks, by compiling them bottom-up into tree
decision diagrams. This package calls tddlog's C library in process.

## Install

```julia
import Pkg
Pkg.add("Tddlog")
```

The package calls the C library of tddlog's release 0.1.1, which it gets as
a lazy Julia artifact: the first call that needs the library downloads it
(about 14 MB) from the
[release](https://github.com/Tractables/tddlog/releases/tag/v0.1.1) and
checks its SHA-256, so installing the package, or a package that depends on
it, downloads nothing. No Rust toolchain and no `tddlog` command are needed.
The package's version is the version of the tddlog release it wraps.

## Platforms

| platform | library |
| --- | --- |
| Linux x86-64 and ARM64 (glibc) | downloaded on first use |
| macOS x86-64 and ARM64 | downloaded on first use |
| Windows x86-64 | by hand, see below |

Windows: the release's Windows archive is a `.zip`, which Pkg cannot unpack.
Download `tddlog-c-v0.1.1-x86_64-pc-windows-msvc.zip` from the release,
unpack it, and set `ENV["TDDLOG_LIBRARY"]` to the path of its `tddlog_c.dll`
before the first call. On a platform without a library, `using Tddlog`
works, and the first call raises an error that says so.

## Another build of the library

`ENV["TDDLOG_LIBRARY"]`, set to the path of a library file before the first
call, loads that file instead of the artifact: a local build of tddlog's C
library (`bindings/c` in tddlog's repository), or the Windows DLL. The
library must be of the same tddlog version, because its interface changes
between releases; another version raises an error. Julia's
[`Overrides.toml`](https://pkgdocs.julialang.org/v1/artifacts/#Overriding-artifact-locations)
works as well: the artifact is `tddlog_c` of the package
`3f2df548-816e-41fe-8d17-dd233152ce24`, and an installation prefix with the
library in `lib/` can take its place.

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
