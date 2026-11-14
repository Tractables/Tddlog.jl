% A probabilistic graph with cycles, an annotated disjunction, negation, a
% probabilistic rule and evidence. test/runtests.jl compares Tddlog.solve's
% answers on it with the tddlog command's.
0.6::edge(1,2).
0.1::edge(1,3).
0.4::edge(2,5).
0.3::edge(2,6).
0.3::edge(3,4).
0.8::edge(4,5).
0.2::edge(5,6).
0.7::edge(6,1).
0.5::edge(5,3).
0.35::edge(4,2).

path(X,Y) :- edge(X,Y).
path(X,Y) :- edge(X,Z), path(Z,Y).

0.3::weather(sun); 0.5::weather(rain); 0.2::weather(snow).
open(X) :- path(1,X), \+weather(snow).
0.9::alarm(X) :- open(X), weather(rain).

evidence(path(1,6), true).
evidence(alarm(6), false).

query(path(1,5)).
query(path(1,6)).
query(path(6,3)).
query(path(3,3)).
query(open(5)).
query(\+open(4)).
query(alarm(5)).
query(weather(rain)).
