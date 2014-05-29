# Intro #

Mfactor is a small interpreter based on a simple VM with some Mfactor
boot code.  It is portable and currently has drivers for linux and
Cortex-M.  The name Mfactor hints at 'embedded Factor' since it aims to
port Factor <http://factorcode.org> to embedded platforms.

# design notes

- non-portable-byte-code interpreter, although mnemonics are portable
- position-independent when using base-relative addressing (stdlib
  only supports base-relative)
- the tradeoff wether to create a new word rather than using a macro
  (inline quotation) starts at 4 primitive instructions on 32-bit
  machines, and 8 primitive instructions on 64 bit machines,
  respectively
- big execution overhead, if anything has to be fast it should be
  specifically compiled

## definitions ##
- cell: datatype used on parameter stack, must be able to hold a pointer
- inst: byte code instruction used in program flow
- base-relative: short, holding an offset pointer relative to base
  address (like segment addressing)

## code layout ##
- byte code, inline-data must be prefixed by corresponding literal
  preserving words (calls, lits, ...)
- byte code words, when used on the stack, are distinguished from
  memory addresses by inspecting the highest bits, i.e. when address
  would point into inaccessible memory, it must be a primitive
  instruction
- last call in a word should always be a tailcall instruction (btcall,
  atcall, stcall), but this is the responsibility of the compiler

## data memory ##
- The only memory handling available in the kernel is getting the
  start and end of readable and writable memory as well as reading and
  writing (unsafely) to arbitrary memory addresses

## parsing ##
- parsing works by accumulating items on the stack (emulates factor's
  accumulation vector)
- parse items are represented by two items on the stack: ITEM TYPE
- command line is special use case, instead of compiling to memory,
  execution is done immediately.  Nonetheless, all parsing words
  should adhere to common interface when nesting, meaning to return
  item/type pairs on the stack, different situations will handle these
  return values differently:
- quotation accumulator will use type flag to compile correct primitive
- data structure accumulators will use type flag to check wether
  parser provided compatible token
- token/word types:
  1. string, byte array
  2. (inline) quotation
  3. vector (not implemented yet)
  4. scalar (useful only if refs are explicit)
  5. words
  6. primitives (byte code instructions)

## boxing/sequences ##
- sequences consist of header containing sequence type ( 2 bytes ),
  element length (1 byte) and sequence length (1 byte for now).
- Sequence accumulation at runtime works by collecting items on the stack until
  finished and exact size of data is known.  This should allow for
  nesting data definitions (through parsing words).  Sequences and
  boxed data are constructed on the stack between nested brace-like
  words, and after a closing bracket the corresponding "load address"
  remains on the stack.
- boxed data includes size and type information.
- types of sequences
  - fixed-element-size-arrays, header information:
    - 1 byte type
  - quotations: like byte-arrays, but don't respond to nth
- sequence access
  - push sequence header elements to stack ( element-size elements type )
  - use functions to work on this "header structure", nth can be
    implemented generically that way (quotations have element size 0
    and cannot be randomly accessed)

## garbage collection (tbd) ##
- root set composed of
  - namestack assocs
  - ref instructions inside quotations
  - refs in parser's accumulation vectors
- mark & compact ensures linear memory scanning 
- types of objects inform gc wether to follow references
  - untyped arrays hold only references to boxed types
  - variables (array length 1) can reference other objects
  - quotations can reference objects via ref instruction
- no focus on performance, since correctly compiled code should not
  rely on garbage collection in most cases, the interpreter itself
  being a notable exception

## types (TODO) ##
- used in complex data
- complex data is represented as |address(31)|1|, whereas fixnums always have LSB=0
- complex data type specifiers are one byte wide, with following layout:

        |type(3)|aux(5)|
  where type indicates:
  - 0: cell(only used in elt-type)
  - 1: fixed-size-sequence, aux is |elt-type(3) | elt-size(2)|
    - element size is (elt-size + 1) ** 2
    - a count byte follows
  - 2: quotation, aux is reserved, no count byte follows
  - 3: user-defined, aux is reserved, the following two bytes specify
    the type location in memory
  - 4: byte-cond, elements are byte -> quotation pairs, used for numeric case statements,
    something akin to jump tables
  - 5: hook (TBD), aux (TBD), in-memory address follows (pointer-type)
- variable type arrays are fixed-size-sequences with elt-type 3 and elt-size 2,
  this basically means an array of boxes
- parser can unbox data on type checks when known at parse time, this
  however requires distinct words that work with unboxed values
- inline data: typed, additional overhead needed since box must be stored
- type system implemented as library instead of language feature
  should allow generic compiler optimization on type checks
- see boxing/sequences above

## stacks ##

### data stack ###
- also called parameter stack, used for all operations

### catch stack (tbd) ###
- exception handling records (place for capturing linear one-shot continuations)

### retain stack ###
- general purpose stack
- _should_ be empty after word exits (TODO: include balance checks in parser)

### return stack ###
- saves return information as well as beginning of word information
  for debugging

# build notes #

- build system: rake
- several ENV vars influence compilation:
  - ONHOST: if set, will be compiled for host system
  - NOPRIVATE: if set, dictionary entries will be generated even for
    words only used internally, useful for tracing (see below)
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

- to build on embedded system (currently supported: cortex-m cores
  either call rake from make, or include the stdlib task in existing
  rake file, and make sure to compile at least `interpreter.c` and the
  reader, as well as the target specific c sources into the final application

# debugging #

- current tools include: using TRACE_LEVEL
- incorporate 'st' calls to print current stack status
- "message" print debugging
- calling `notail` which disables tail calls, thus leaving the return
  stack completely intact
  - NOTE: if necessary, increase VM_RETURNSTACK (either on command
    line or in interpreter.h", since currently all looping constructs
    including the top level listener are implemented with tail recursion
  - tail calling can be reactivated with `tail`

# caveats #
- at the moment the gc is not implemented yet, so you will eventually
  run out of memory if not careful.  current memory usage can be
  checked with the word `usage`
