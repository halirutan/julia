(* Benchmark script *)

(* Set up output stream *)
SetOptions[$Output, FormatType -> OutputForm];

(* Test if system has a C compiler and if so set target to "C"*)
Needs["CCompilerDriver`"];
If[ Length[CCompilers[]] > 0,
    $CompilationTarget = "C"
];


ClearAll[$printOutput];
$printOutput = True;


(* Using RepeatedTiming instead of AbsoluteTiming *)
ClearAll[timeit];
SetAttributes[timeit, HoldFirst];
timeit[ex_, name_String] := Module[
    {t},
    t = Infinity;
    Do[
        t = Min[t, N[First[AbsoluteTiming[ex]]]];
        ,
        {i, 1, 20}
    ];
    If[$printOutput,
        Print["mathematica,", name, ",", t * 1000];
    ];
];

ClearAll[test];
SetAttributes[test, HoldFirst];
test[ex_] := Assert[ex];
On[Assert];

(* recursive fib *)

ClearAll[fib];
fib = Compile[{{n, _Integer}},
    If[n < 2, n, fib[n - 1] + fib[n - 2]],
    CompilationTarget -> "WVM"
];

test[fib[20] == 6765];
timeit[fib[20], "fib"];

(* parse integer *)

ClearAll[parseintperf];
parseintperf[t_] := Module[
    {n, m, i, s},
    Do[
        n = RandomInteger[{0, 4294967295}];
        s = IntegerString[n, 16];
        m = FromDigits[s, 16];
        ,
        {i, 1, t}
    ];
    test[ m == n];
    n
];

timeit[parseintperf[1000], "parse_int"];

(* array constructors *)

test[ DeleteDuplicates[Flatten[ConstantArray[1, {200, 200}]]] == {1}];

(* matmul and transpose *)

ClearAll[A];
With[{arr = ConstantArray[1, {200, 200}]},
    test[DeleteDuplicates[Flatten[arr.ConjugateTranspose[arr]]] == {200}];
];

(* mandelbrot set: complex arithmetic and comprehensions *)

(* Old implementation *)

mandelOld = Compile[{{zin, _Complex}},
    Module[
        {z = zin, c = zin, maxiter = 80, n = 0},
        Do[
            If[ Abs[z] > 2,
                maxiter = n - 1;
                Break[]
            ];
            z = z^2 + c;
            ,
            {n, 1, maxiter}
        ];
        maxiter
    ]
];

ClearAll[mandelperfOld];
mandelperfOld[] := Table[mandelOld[r + i * I], {i, -1., 1., 0.1}, {r, -2.0, 0.5, 0.1}];

test[ Total[mandelperfOld[], 2] == 14791];
timeit[mandelperfOld[], "mandelOld"];

(* Vectorized list comprehension *)

mandel = Compile[{{zin, _Complex}},
    Module[
        {
            z = zin,
            c = zin,
            maxiter = 80,
            n = 0
        },
        Do[
            If[Abs[z] > 2,
                maxiter = n - 1;
                Break[]
            ];
            z = z^2 + c,
            {n, 1, maxiter}
        ];
        maxiter],
    RuntimeAttributes -> {Listable},
    Parallelization -> True,
    RuntimeOptions -> "Speed",
    CompilationTarget -> "C"
];
mandelperf[] := mandel@Table[r + i * I, {i, -1., 1., 0.1}, {r, -2.0, 0.5, 0.1}];

test[ Total[mandelperf[], 2] == 14791];
timeit[mandelperf[], "mandel"];

(* numeric vector sort *)

(* Old implementation *)

qsortOld = Compile[
    {{ain, _Real, 1}, {loin, _Integer}, {hiin, _Integer}},
    Module[
        {a = ain, i = loin, j = hiin, lo = loin, hi = hiin, pivot},
        While[ i < hi,
            pivot = a[[ Floor[(lo + hi) / 2] ]];
            While[ i <= j,
                While[a[[i]] < pivot, i++];
                While[a[[j]] > pivot, j--];
                If[ i <= j,
                    a[[{i, j}]] = a[[{j, i}]];
                    i++; j--;
                ];
            ];
            If[ lo < j, a[[lo ;; j]] = qsortOld[ a[[lo ;; j]], 1, j - lo + 1] ];
            {lo, j} = {i, hi};
        ];
        a
    ]
];


ClearAll[sortperfOld];
sortperfOld[n_] := Module[{vec = RandomReal[1, n]}, qsortOld[vec, 1, n]];

test[OrderedQ[sortperfOld[5000]] ];
timeit[sortperfOld[5000], "quicksortOld"];

(* New implementation *)

qsort = Compile[{{ain, _Real, 1}},
    Module[
        {
            a = ain, i = 0, j = 0, lo = 1, hi = Length[ain], pivot,
            stack = {1}, $s = 0
        },
        stack = Table[0, {Floor[Log[2, hi]^2 / 2]}];
        stack[[++$s]] = 1;
        stack[[++$s]] = Length[ain];
        While[$s > 0,
            hi = j = stack[[$s--]];
            lo = i = stack[[$s--]];
            While[i < hi,
                pivot = a[[Floor[(lo + hi) / 2]]];
                While[i <= j,
                    While[a[[i]] < pivot, ++i];
                    While[a[[j]] > pivot, --j];
                    If[i <= j,
                        a[[{i, j}]] = a[[{j--, i++}]];
                    ];
                ];
                If[lo < j,
                    stack[[++$s]] = lo;
                    stack[[++$s]] = j;
                ];
                {lo, j} = {i, hi};]
        ];
        a
    ],
    CompilationTarget -> "C",
    RuntimeOptions -> "Speed"
];
sortperf[n_] := Module[{vec = RandomReal[1, n]}, qsort[vec]];

test[OrderedQ[sortperf[5000]]];
timeit[sortperf[5000], "quicksort"];

(* slow pi series  *)

(* Old implementation *)

pisumOld = Compile[ {},
    Module[
        {sum = 0.`},
        Do[sum = Sum[1 / (k * k), {k, 1, 10000}],
            {500}];
        sum
    ]
];


test[Abs[pisumOld[] - 1.644834071848065`] < 1.`*^-12 ];
timeit[pisumOld[], "pi_sumOld"];

(* New implementation *)

pisum = Compile[{}, Module[{sum = 0., n = 10000},
    Do[
        sum = 0.0;
        Do[sum += 1.0 / (k * k), {k, n}], {500}
    ];
    sum],
    CompilationTarget -> "C",
    RuntimeOptions -> "Speed"
];

test[Abs[pisum[] - 1.644834071848065`] < 1.`*^-12 ];
timeit[pisum[], "pi_sum"];

(* slow pi series, vectorized *)

pisumvec = Compile[{},
    Module[
        {sum = 0.},
        Do[
            sum = Total[1 / Range[1, 10000]^2];,
            {500}
        ];
        sum
    ]
];

test[Abs[pisumvec[] - 1.644834071848065`] < 1.`*^-12 ];
timeit[pisumvec[], "pi_sum_vec"];


(* random matrix statistics *)

randmatstatOld = Compile[{{t, _Integer}},
    Module[
        {
            n = 5,
            v = ConstantArray[0., t],
            w = ConstantArray[0., t],
            a = {{0.}}, b = {{0.}},
            c = {{0.}}, d = {{0.}},
            P = {{0.}}, Q = {{0.}}
        },
        Do[
            a = RandomReal[NormalDistribution[], {n, n}];
            b = RandomReal[NormalDistribution[], {n, n}];
            c = RandomReal[NormalDistribution[], {n, n}];
            d = RandomReal[NormalDistribution[], {n, n}];
            P = Join[a, b, c, d, 2];
            Q = ArrayFlatten[{{a, b}, {c, d}}];
            v[[i]] = Tr[MatrixPower[Transpose[P].P, 4]];
            w[[i]] = Tr[MatrixPower[Transpose[Q].Q, 4]];
            ,
            {i, 1, t}
        ];
        {StandardDeviation[v] / Mean[v], StandardDeviation[w] / Mean[w]}
    ],
    {{_ArrayFlatten, _Real, 2}}
];


ClearAll[s1, s2];
{s1, s2} = randmatstatOld[1000];
test[0.5 < s1 < 1.0 && 0.5 < s2 < 1.0];

timeit[randmatstatOld[1000], "rand_mat_stat"];


(* largish random number gen & matmul *)

timeit[RandomReal[1, {1000, 1000}].RandomReal[1, {1000, 1000}], "rand_mat_mul"];

(* printfd *)

(* only on unix systems *)
If[ $OperatingSystem == "Unix" || $OperatingSystem == "MacOSX",

    ClearAll[printfd];
    printfd[n_] := Module[
        {stream},
        stream = OpenWrite["/dev/null"];
        Do[
            WriteString[stream, i, " ", i + 1, "\n" ];
            ,
            {i, 1, n}
        ];
        Close[stream];
    ];

    timeit[printfd[100000], "printfd"];

];
