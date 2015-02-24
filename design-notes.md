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

## cross compilation ##

- CURRENT: The host implementation currently parses a subset of
  factor's syntax word, namely: `:`, `SYNTAX:`, `B{ }`
- PLANNED: The host implementation contains a bootstrapping ruby
  loader, which is able to parse simple source files containing only
  `:`, `SYNTAX:` and `PRIM:` definitions.  Once these are used to
  generate a minimal image, other immediate words can be used.  In
  essence, while creating the image, a parse-time specialized image is
  used to build the actual image.  Once the image is built, it can be
  converted to bytecode form.  This byte code form can either be
  compiled to a c array suitable for interpretation, compiled to
  statically typed c source code (TBD) or executed in ruby, essentially
  providing a simulator for the VM.

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
- fixed-element-width sequences consist of header containing sequence header (codes element-type and -size) byte
  and sequence length (1 byte for now) preceeding the content.
- Sequence accumulation at runtime works by collecting items on the stack until
  finished and exact size of data is known.  This should allow for
  nesting data definitions (through parsing words).  Sequences and
  boxed data are constructed on the stack between nested brace-like
  words, and after a closing bracket the corresponding "load address"
  remains on the stack.
- sequence access
  - push pointer to first element of sequence to stack
  - either use access function directly (unsafe)
  - or use type-checking function, which does a look-behind in memory
  - use functions to work on this "header structure", nth can be
    implemented generically that way
  - if scalar value is on stack, this will still not be caught, since there is no way to
    distiguish between scalar values and sequences (yet)

## garbage collection (tbd) ##
- root set composed of
  - namestack assocs
  - ref instructions inside quotations
  - refs in parser's accumulation vectors
  - imprecise stack elements (bad solution)
- mark & compact ensures linear memory scanning 
- types of objects inform gc wether to follow references
  - untyped arrays hold only references to boxed types
  - variables (array length 1) can reference other objects
  - quotations can reference objects via ref instruction
- no focus on performance, since correctly compiled code should not
  rely on garbage collection in most cases, the interpreter itself
  being a notable exception

## user types (TODO) ##
- usage in code indicated by instruction, which refers to the type object itself (needs parser support)
- parser can unbox data on type checks when known at parse time, this
  however requires distinct words that work with unboxed values
- inline data: typed, additional overhead needed since box must be stored
- type system implemented as library instead of language feature
  should allow generic compiler optimization on type checks

## stacks ##

### data stack ###
- also called parameter stack, used for all operations

### catch stack (tbd) ###
- exception handling records (place for capturing linear one-shot continuations)

### retain stack ###
- general purpose stack
- must be empty after word definition is done
- must be balanced inside a quotation (e.g. `1 >r [ r> 1 +] [ r> 4 + ]` not allowed)
- could be merged into return stack, but then call frame debug information is lost

### return stack ###
- saves return information as well as beginning of word information
  for debugging
