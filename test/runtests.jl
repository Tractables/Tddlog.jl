using Test
using Tddlog

# The answers of the hand-computed tests are exact up to rounding.
approx(a, b) = isapprox(a, b; atol = 1e-12)
answers_approx(s, expected) =
    s.answers !== nothing && first.(s.answers) == first.(expected) &&
    all(approx(p, q) for ((_, p), (_, q)) in zip(s.answers, expected))

const ALARM = """
0.1::burglary.
0.2::earthquake.
0.7::hears_alarm(john).
0.4::hears_alarm(mary).
alarm :- burglary.
alarm :- earthquake.
calls(X) :- alarm, hears_alarm(X).
evidence(calls(john), true).
query(burglary).
query(earthquake).
query(calls(mary)).
"""

const NEGATION = """
0.3::a.
0.6::b.
c :- a, \\+b.
0.2::x(1); 0.5::x(2).
neither :- \\+x(1), \\+x(2).
query(c).
query(\\+c).
query(x(1)).
query(x(2)).
query(neither).
"""

const CYCLE = """
0.5::edge(a,b).
0.5::edge(b,a).
0.5::edge(b,c).
path(X,Y) :- edge(X,Y).
path(X,Y) :- edge(X,Z), path(Z,Y).
query(path(a,c)).
query(path(a,a)).
query(path(b,b)).
query(path(c,a)).
"""

const INCONSISTENT = """
0.4::a.
b :- a.
evidence(a, true).
evidence(b, false).
query(a).
"""

@testset "Tddlog" begin
    @testset "version" begin
        @test Tddlog.version() isa VersionNumber
        @test Tddlog.version() == pkgversion(Tddlog)
    end

    @testset "evidence" begin
        # P(alarm) = 1 - 0.9 * 0.8 = 0.28 and P(e) = P(calls(john)) = 0.28 * 0.7 = 0.196;
        # P(burglary | e) = 0.1 * 0.7 / 0.196 = 5/14, P(earthquake | e) = 0.2 * 0.7 / 0.196
        # = 5/7, P(calls(mary) | e) = 0.4.
        s = solve(ALARM)
        @test s isa Solution
        @test s.consistent
        @test answers_approx(s, ["burglary" => 5 / 14, "earthquake" => 5 / 7, "calls(mary)" => 0.4])
        @test s.evidence_probability === nothing
        @test s.log10_evidence_probability === nothing
        @test approx(Dict(s.answers)["calls(mary)"], 0.4)

        s = solve(ALARM; evidence_probability = true)
        @test answers_approx(s, ["burglary" => 5 / 14, "earthquake" => 5 / 7, "calls(mary)" => 0.4])
        @test approx(s.evidence_probability, 0.196)
        @test approx(s.log10_evidence_probability, log10(0.196))

        s = solve(ALARM; evidence_probability = true, queries = false)
        @test s.consistent
        @test s.answers == Pair{String, Float64}[]
        @test approx(s.evidence_probability, 0.196)

        s = solve("0.4::a.\nquery(a).\n"; evidence_probability = true)
        @test answers_approx(s, ["a" => 0.4])
        @test s.evidence_probability == 1.0
        @test s.log10_evidence_probability == 0.0

        # 400 independent observations of probability 1/10 each: P(e) = 1e-400,
        # under the least Float64, whose logarithm is still exact.
        facts = join("0.1::f($i). evidence(f($i), true). " for i in 0:399)
        s = solve(facts * "0.5::q. query(q)."; evidence_probability = true)
        @test answers_approx(s, ["q" => 0.5])
        @test s.evidence_probability == 0.0
        @test isapprox(s.log10_evidence_probability, -400.0; atol = 1e-9)
    end

    @testset "negation and annotated disjunctions" begin
        # P(c) = 0.3 * 0.4; neither x(1) nor x(2): 1 - 0.2 - 0.5.
        s = solve(NEGATION)
        @test answers_approx(s, ["c" => 0.12, "\\+c" => 0.88, "x(1)" => 0.2, "x(2)" => 0.5,
                                 "neither" => 0.3])
    end

    @testset "cycles" begin
        # Each path is one two-edge walk: a->b->c, a->b->a, b->a->b; c has no edge out.
        s = solve(CYCLE)
        @test answers_approx(s, ["path(a,c)" => 0.25, "path(a,a)" => 0.25, "path(b,b)" => 0.25,
                                 "path(c,a)" => 0.0])
        for vtree in ("auto", "td", "program")
            @test answers_approx(solve(CYCLE; vtree), s.answers)
        end
    end

    @testset "arguments" begin
        program = "0.25::q(a).\n0.75::q(b).\np :- q(\$1).\nquery(p).\n"
        @test answers_approx(solve(program; arguments = ["a"]), ["p" => 0.25])
        @test answers_approx(solve(program; arguments = ["b"]), ["p" => 0.75])
    end

    @testset "inconsistent evidence" begin
        s = solve(INCONSISTENT)
        @test !s.consistent
        @test s.answers === nothing
        @test s.evidence_probability === nothing
        s = solve(INCONSISTENT; evidence_probability = true)
        @test !s.consistent
        @test s.answers === nothing
        @test s.evidence_probability == 0.0
        @test s.log10_evidence_probability == -Inf
    end

    @testset "errors" begin
        @test_throws Tddlog.ParseError solve("p :- q(.")
        err = try
            solve("p :- q(.")
        catch e
            e
        end
        @test err isa Tddlog.Error
        @test !isempty(err.msg)
        @test occursin("Tddlog.ParseError: ", sprint(showerror, err))

        @test_throws Tddlog.GroundingError solve("p :- X > 1. query(p).")
        # a and b are undefined in every world of this program, so no
        # probability exists (Bogaerts and Van den Broeck 2015, Example 4.15)
        unsound = "0.5::e.\na :- \\+b.\nb :- \\+a.\nc :- \\+b.\nc :- e.\nd :- a, \\+c.\nquery(a).\nquery(d).\n"
        err = try
            solve(unsound)
        catch e
            e
        end
        @test err isa Tddlog.CompilationError
        @test occursin("well-founded", err.msg)

        @test_throws ArgumentError solve("0.5::a.\nquery(a).\n"; format = "nope")
        @test_throws ArgumentError solve("0.5::a.\nquery(a).\n"; vtree = "nope")
        @test_throws ArgumentError solve("0.5::a.\nquery(a).\n"; queries = false)
        @test_throws ArgumentError solve("0.5::a.\nquery(a).\n"; evidence = "")
        @test_throws ArgumentError solve("0.5::a.\0\nquery(a).\n")
        @test_throws MethodError solve("0.5::a.\nquery(a).\n"; vtre = "auto")

        # after an error, the next call answers
        @test answers_approx(solve("0.5::a.\nquery(a).\n"), ["a" => 0.5])
    end

    # The answers of the tddlog command of the same release, given as
    # ENV["TDDLOG_COMMAND"]: printed with 25 digits after the point, they
    # parse back to the same Float64s.
    @testset "the tddlog command" begin
        command = get(ENV, "TDDLOG_COMMAND", "")
        if isempty(command)
            @info "ENV[\"TDDLOG_COMMAND\"] is not set: the answers are not compared with the tddlog command's"
            @test_skip false
        else
            cmd = Cmd(Base.shell_split(command))
            @test VersionNumber(split(readchomp(`$cmd --version`))[end]) == Tddlog.version()
            file = joinpath(@__DIR__, "programs", "graph.pl")
            for pe in (false, true)
                out = read(`$cmd --precision 25 $(pe ? ["--evidence-probability"] : String[]) $file`, String)
                answers = Pair{String, Float64}[]
                evidence = nothing
                for line in eachline(IOBuffer(out))
                    m = match(r"^P\(e\):\t(\S+)\tlog10 (\S+)$", line)
                    if m !== nothing
                        evidence = (parse(Float64, m[1]), parse(Float64, m[2]))
                        continue
                    end
                    m = match(r"^(\S+):\t(\S+)$", line)
                    m === nothing || push!(answers, m[1] => parse(Float64, m[2]))
                end
                s = solve(read(file, String); evidence_probability = pe)
                @test length(answers) == 8
                @test s.answers == answers
                if pe
                    @test (s.evidence_probability, s.log10_evidence_probability) == evidence
                end
                @info "graph.pl, evidence_probability = $pe" s
            end
        end
    end
end
