# Intro #

Mfactor is a small interpreter based on a simple VM with some Mfactor
boot code.  It aims to be portable and currently has drivers for linux(64 bit) and
Cortex-M.  The name Mfactor hints at 'embedded Factor' since it aims to
port Factor <http://factorcode.org> to embedded platforms.  No memory management is required.

# differences to factor
Mfactor implements a subset of factor's functionality useful for embedded systems programming.
Major differences:
- no namestack, so no dynamic variables (may change, but high
  performance impact for embedded systems)
- vocabulary search is simplified, vocabulary foo would be found in
  <any-vocab-root>/foo.mfactor, vocabulary foo.bar would be found in
  <any-vocab-root>/foo/bar.mfactor.
- same-named words in different vocabularies not supported (yet)
- built-in support only for byte-array and integer-array sequences
- host compiler only supports a subset of syntax words: `:`, `SYNTAX:`, `B{ }`, `I{ }`,
- words beginning with underscore(`_`) are not stored in the
  dictionary.  This prevents helper functions from consuming
  dictionary space.
- no continuations, no quotation compositions(yet)
- simplified exception handling with `catch` and `throw`

# compilation #

## to bytecode ##
Source files are read vocbulary-wise and converted into bytecode.

## to-source (WIP) ##
Compilation (to graphs, and later source code) works by "virtual interpretation", a technique for compiling
stack-based languages described here: http://www.complang.tuwien.ac.at/projects/rafts.html

Right now, a combined Control-/Dataflow graph is constructed, which is
used as intermediate representation. This graph can be output in dot format for
visual inspection of the workings of a word.  All combinators are inlined automatically.
This is because the target output is C, which does not support higher order functions.

# build notes #

## usage ##

To build on embedded system (currently supported: cortex-m cores)
- Either call rake from make, or include the `stdlib` task in existing
  rake file.  When including the `stdlib` file, several ruby constants
  influence behaviour.  See "tasks/stdlib.task" for default values.
  These values must be defined at minimum:
  - `MFACTOR_SRC_DIR`, where to search for mfactor source files
  - `MFACTOR_ROOT_VOCAB`, starting point for bytecode generation, should be the application's main source file.
  - `START_WORD`, where to 
  - `GENERATOR`, determines target platform, either `Cortex` or `Linux64`
- Make sure to compile at least `interpreter.c` and the
  reader, as well as the target specific c sources into the final
  application in your existing build system.
- All generated artifacts (code, graphs, logs) are put
  into the "generated" subdirectory of the working directory of the
  rake call.
- Calling rake with the `--trace` option causes verbose output during compilation.

## interfacing to existing c code ##
- Special global variable `mfactor_ff` can be set to a yaml file for
  "importing" existing c functions into the interpreter's namespace (Foreign function interface).
  entries are in the form of

        c_name:
			name: "mfactor-name"
			call: <callspec>

  where <callspec> describes the function's arguments, e.g. "iis" for a function like `fn( int, int, int)`.
  Currently supported values are:
  - `v` -> fn(void)
  - `lit` -> for variables
  - `i`, `b`, `bi`, `iis`, `iii` where `i` is `int`, `b` is `int8` and `s` is `int16`

## Other Notes ##
- build system: rake
- several ENV vars influence compilation:
  - ONHOST: if set, will be compiled for host system
  - NOPRIVATE: if set, dictionary entries will be generated even for
    words only used internally.  useful for tracing (see below), but
    requires big dictionary sizes for code-bases with a lot of definitions
  - NOTAIL: disable tail calls at start, can be switched on and off
    with `tail` and `notail` instructions nonetheless
- compile time switches:
  - TRACE_LEVEL: controls execution trace information on standard output
    - 0: no trace output
    - 1: word lookup and basic execution tracing
    - 2: full execution tracing
- example to build and run on linux host:

        rake ONHOST=1 NOPRIVATE=1
        ./mfactor


# debugging #

- current tools include: using TRACE_LEVEL
- incorporate 'st' calls to print current stack status
- calling `notail` which disables tail calls, thus leaving the return
  stack completely intact
  - NOTE: if necessary, increase VM_RETURNSTACK (either on command
    line or in interpreter.h", since currently all looping constructs
    including the top level listener are implemented with tail recursion
  - tail calling can be reactivated with `tail`
- recursive invocation of interpreter in case of error, allows interactive inspection of stacks

# caveats #
- At the moment the gc is not implemented yet (allocation only takes
  place at parse-time during interaction except when done explicitely
  in the application), so you could run out of memory if excessive
  number of words, strings, or sequences are created interactively.
  Current memory usage can be checked with the word `usage`


