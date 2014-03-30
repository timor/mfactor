# design notes
- non-portable-byte-code interpreter, although mnemonics are portable
- position-independent when using base-relative addressing (stdlib
  only supports base-relative)
- the tradeoff wether to create a new word rather than using a macro
  (inline quotation) starts at 4 primitive instructions on 32-bit
  machines, and 8 primitive instructions on 64 bit machines,
  respectively
- cstrings are null-terminated (remove!)
- big execution overhead, if anything has to be fast it should be
  specifically compiled

## definitions ##
- cell: datatype used on parameter stack, must be able to hold a pointer
- inst: byte code instruction used in program flow
- base-relative: short, holding an offset pointer relative to base
  address (like segment addressing)

# code layout #
- byte code, inline-data must be prefixed by corresponding literal
  preserving words (calls, lits, ...)
- byte code words are distinguished from memory address by inspecting
  the highest bits when used on the stack, i.e. when address would
  point into inaccessible memory, it must be a primitive instruction

# data memory #
- The only memory handling available in the kernel is getting the
  start and end of readable and writable memory as well as reading and
  writing (unsafely) to arbitrary memory addresses
- Sequence accumulation works by collecting items on the stack until
  finished and exact size of data is known.  This should allow for
  nesting data definitions.  Sequences and boxed data are constructed
  on the stack between nested brace-like words, and after a closing
  bracket the corresponding "load address" remains on the stack.
- garbage collection support relies on explicit ref instructions
  from quotations, which have the same runtime effect as lits
- boxed data includes size and type information.
## boxing/sequences ##
- sequences consist of header containing sequence type ( 2 bytes ),
  element length (1 byte) and sequence length (1 byte for now).
- types of sequences
  - arrays: one type field overhead per element
  - byte-arrays: for strings
  - quotations: like byte-arrays, but don't respond to nth

- sequence access
  - push sequence header elements to stack ( element-size elements type )
  - use functions to work on this "header structure", nth can be
    implemented generically that way

# types (TODO) #
- used in boxed data
- for data on stack, type stack holds rtti
- parser can unbox data on type checks when known at parse time, this
  however requires distinct words that work with unboxed values
- 2 strategies for inline data:
  - untyped, make sure compiler does all necessary checks
  - typed, additional overhead needed since box must be stored

# stacks #

## data stack ##

## catch stack ##
- exception handling records (continuations, actually)
- naiive implementation, copying all other stacks onto the catch stack

## retain stack ##
- general purpose stack
- must be empty after word exits (TODO: include balance checks in parser)

## return stack ##
- saves return information as well as beginning of word information
  for debugging


## build notes ##

- build system: rake
- several ENV vars influence compilation:
  - ONHOST: if set, will be compiled for host system
  - NOPRIVATE: if set, dictionary entries will be generated even for
    words only used internally, useful for tracing (see below)
  - NOTAILCALL: if set, don't use tail calls at all.  Useful for debugging,
    but limits operations massively since all loops are implemented recursively
- compile time switches:
  - TRACE_LEVEL: controls execution trace information on standard output
    - 0: no trace output
    - 1: basic word lookup tracing
    - 2: full execution tracing
- example:

        rake ONHOST=1 NOPRIVATE=1
        ./mfactor

