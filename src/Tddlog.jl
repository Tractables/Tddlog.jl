"""
    Tddlog

Exact probabilistic inference with [tddlog](https://github.com/Tractables/tddlog):
the probabilities of the queries of a ProbLog program, an LPAD, a Dice
program, a Circulette netlist or a Bayesian or Markov network, computed in
process by tddlog's C library. [`solve`](@ref) answers a program and returns a
[`Solution`](@ref).
"""
module Tddlog

using Artifacts: artifact_exists, artifact_meta, artifact_path
using Libdl: Libdl

export solve, Solution

# The tddlog release whose C library this package calls; its ABI changes
# between releases, so the library loaded must be this one.
const TDDLOG_VERSION = v"0.1.1"

const ARTIFACTS_TOML = joinpath(dirname(@__DIR__), "Artifacts.toml")

##################################
# Errors
##################################

"""
A program tddlog could not answer: the supertype of [`ParseError`](@ref),
[`GroundingError`](@ref) and [`CompilationError`](@ref). Options that break
the library's contract raise an `ArgumentError` instead.
"""
abstract type Error <: Exception end

"The program is not in the language or the format it is said to be in."
struct ParseError <: Error
    msg::String
end

"""
The program parses but cannot be ground: an unsupported construct or a rule
that is not range restricted.
"""
struct GroundingError <: Error
    msg::String
end

"""
The ground program could not be compiled and counted under the vtree
strategy asked for, or the well-founded model of some world leaves an atom
undefined.
"""
struct CompilationError <: Error
    msg::String
end

Base.showerror(io::IO, e::Error) = print(io, "Tddlog.", nameof(typeof(e)), ": ", e.msg)

# The exception for a status of tddlog_solve other than TDDLOG_OK (0).
function status_error(status, msg)
    status == 1 && return ArgumentError(msg)
    status == 2 && return ParseError(msg)
    status == 3 && return GroundingError(msg)
    status == 4 && return CompilationError(msg)
    status == 5 && return ErrorException("tddlog panicked, a bug to report: $msg")
    ErrorException("tddlog_solve returned the unknown status $status: $msg")
end

##################################
# The library
##################################

# The entry points of tddlog's C library (bindings/c/include/tddlog.h), each
# field the function `tddlog_<field>`.
struct Library
    path::String
    version::Ptr{Cvoid}
    last_error_message::Ptr{Cvoid}
    solve::Ptr{Cvoid}
    solution_free::Ptr{Cvoid}
    solution_consistent::Ptr{Cvoid}
    solution_num_answers::Ptr{Cvoid}
    solution_query::Ptr{Cvoid}
    solution_probability::Ptr{Cvoid}
    solution_evidence_probability::Ptr{Cvoid}
end

# The library, or why it could not be loaded; set by __init__.
const LIBRARY = Ref{Union{Library, String}}("Tddlog is not initialized")

function unsupported_platform()
    platform = Base.BinaryPlatforms.triplet(Base.BinaryPlatforms.HostPlatform())
    """tddlog's release $TDDLOG_VERSION has no C library for $platform that Julia can \
    install; it has Linux (x86-64 and ARM64, glibc) and macOS (x86-64 and ARM64). On \
    Windows, unpack tddlog-c-v$TDDLOG_VERSION-x86_64-pc-windows-msvc.zip from \
    https://github.com/Tractables/tddlog/releases/tag/v$TDDLOG_VERSION and set \
    ENV["TDDLOG_LIBRARY"] to the path of its tddlog_c.dll before loading Tddlog."""
end

# The library file in this platform's artifact.
function artifact_library()
    meta = artifact_meta("tddlog_c", ARTIFACTS_TOML)
    meta === nothing && error(unsupported_platform())
    hash = Base.SHA1(meta["git-tree-sha1"])
    artifact_exists(hash) ||
        error("tddlog's C library is not installed: run `import Pkg; Pkg.instantiate()`")
    root = artifact_path(hash)
    name = Sys.isapple() ? "libtddlog_c.dylib" : "libtddlog_c.so"
    for dir in readdir(root; join = true)
        file = joinpath(dir, "lib", name)
        isfile(file) && return file
    end
    error("tddlog's C library $name is not in $root")
end

function load_library()
    path = get(ENV, "TDDLOG_LIBRARY", "")
    isempty(path) && (path = artifact_library())
    handle = Libdl.dlopen(path)
    entries = (Libdl.dlsym(handle, Symbol("tddlog_", f)) for f in fieldnames(Library)[2:end])
    lib = Library(path, entries...)
    v = unsafe_string(ccall(lib.version, Cstring, ()))
    v == string(TDDLOG_VERSION) ||
        error("Tddlog.jl calls tddlog's C library $TDDLOG_VERSION, and $path is $v")
    lib
end

function __init__()
    LIBRARY[] = try
        load_library()
    catch e
        e isa ErrorException ? e.msg : sprint(showerror, e)
    end
    nothing
end

function library()
    lib = LIBRARY[]
    lib isa Library || error(lib)
    lib
end

"""
    Tddlog.version() -> VersionNumber

The version of the tddlog release whose C library answers [`solve`](@ref).
"""
version() = VersionNumber(unsafe_string(ccall(library().version, Cstring, ())))

##################################
# Solving
##################################

# TddlogOptions, field for field.
struct Options
    vtree::Cstring
    evidence_probability::Bool
    queries::Bool
    format::Cstring
    evidence::Cstring
    arguments::Ptr{Cstring}
    num_arguments::Csize_t
end

# A pointer to the text of `s`, which the caller preserves; an
# ArgumentError where it holds a NUL.
cstring(s::String) = Base.unsafe_convert(Cstring, s)
cstring(::Nothing) = Cstring(C_NULL)

"""
    Solution

The answers to a program's queries, and the probability of its evidence
where [`solve`](@ref) was asked for it:

- `answers`: each query, as ProbLog prints it (`\\+p` for a `query(\\+p)`),
  paired with its probability, in the program's order; `nothing` where the
  evidence is inconsistent, empty with `queries = false`. `Dict(s.answers)`
  looks them up by query.
- `consistent`: whether the evidence is consistent.
- `evidence_probability`: P(e), for a UAI network the partition function
  given the evidence; `nothing` unless asked for. It is 1 with no evidence,
  and 0 with inconsistent evidence or under the least `Float64`.
- `log10_evidence_probability`: the base-10 logarithm of P(e), exact beyond
  a `Float64`'s range; `nothing` unless asked for.
"""
struct Solution
    answers::Union{Nothing, Vector{Pair{String, Float64}}}
    consistent::Bool
    evidence_probability::Union{Nothing, Float64}
    log10_evidence_probability::Union{Nothing, Float64}
end

function Base.show(io::IO, ::MIME"text/plain", s::Solution)
    print(io, "Tddlog.Solution")
    if s.answers === nothing
        print(io, "\n  evidence is inconsistent")
    else
        for (query, p) in s.answers
            print(io, "\n  ", query, ":\t", p)
        end
    end
    s.evidence_probability === nothing ||
        print(io, "\n  P(e):\t", s.evidence_probability, "\tlog10 ", s.log10_evidence_probability)
end

"""
    solve(program; format = "problog", evidence = nothing, vtree = "auto",
          evidence_probability = false, queries = true, arguments = String[]) -> Solution

Answer the queries of `program`, given as text, as the `tddlog` command does
for a file holding it.

- `format`: what the text is, as the command tells it by the file's
  extension: `"problog"` (an LPAD where it holds `:- begin_lpad.`), `"dice"`,
  `"circulette"`, or a network's, `"bif"`, `"hugin"`, `"xdsl"` or `"uai"`,
  with every variable queried.
- `evidence`: for a network, the text of its evidence file (an Ace `.inst`
  file, or a UAI `.evid` file for a UAI network).
- `vtree`: the vtree strategy, the command's `--vtree`.
- `evidence_probability`: also compute P(e), the probability of the
  evidence; the evidence no query depends on is then compiled rather than
  dropped.
- `queries`: `false` leaves the queries out, as `--no-queries` does, and
  needs `evidence_probability`.
- `arguments`: the terms that take the places `\$1`, `\$2`, ... of a ProbLog
  program, an LPAD or a Dice program (of a Dice program, natural numbers).

A keyword not listed is a `MethodError`. Options that break the library's
contract (an unknown format or strategy, evidence for a program that is not
a network, options that ask for nothing) raise an `ArgumentError`; a program
tddlog cannot answer raises a [`Tddlog.Error`](@ref).
"""
function solve(program::AbstractString;
               format::AbstractString = "problog",
               evidence::Union{Nothing, AbstractString} = nothing,
               vtree::AbstractString = "auto",
               evidence_probability::Bool = false,
               queries::Bool = true,
               arguments::AbstractVector{<:AbstractString} = String[])
    lib = library()
    program, format, vtree = String(program), String(format), String(vtree)
    evidence = evidence === nothing ? nothing : String(evidence)
    args = String[String(a) for a in arguments]
    out = Ref{Ptr{Cvoid}}(C_NULL)
    status = GC.@preserve program format vtree evidence args begin
        argv = Cstring[cstring(a) for a in args]
        GC.@preserve argv begin
            options = Ref(Options(cstring(vtree), evidence_probability, queries, cstring(format),
                                  cstring(evidence),
                                  isempty(argv) ? Ptr{Cstring}(C_NULL) : pointer(argv),
                                  length(argv)))
            s = ccall(lib.solve, Int32, (Cstring, Ref{Options}, Ref{Ptr{Cvoid}}),
                      cstring(program), options, out)
            # The message is the calling thread's, so it is read before
            # anything can yield.
            s == 0 ? (s, "") : (s, unsafe_string(ccall(lib.last_error_message, Cstring, ())))
        end
    end
    status[1] == 0 || throw(status_error(status...))
    solution = out[]
    try
        consistent = ccall(lib.solution_consistent, Bool, (Ptr{Cvoid},), solution)
        n = ccall(lib.solution_num_answers, Csize_t, (Ptr{Cvoid},), solution)
        answers = if consistent
            Pair{String, Float64}[
                unsafe_string(ccall(lib.solution_query, Cstring, (Ptr{Cvoid}, Csize_t), solution, i)) =>
                ccall(lib.solution_probability, Cdouble, (Ptr{Cvoid}, Csize_t), solution, i)
                for i in 0:(Int(n) - 1)]
        else
            nothing
        end
        p, log10p = Ref(NaN), Ref(NaN)
        asked = ccall(lib.solution_evidence_probability, Bool,
                      (Ptr{Cvoid}, Ref{Cdouble}, Ref{Cdouble}), solution, p, log10p)
        Solution(answers, consistent, asked ? p[] : nothing, asked ? log10p[] : nothing)
    finally
        ccall(lib.solution_free, Cvoid, (Ptr{Cvoid},), solution)
    end
end

end # module
