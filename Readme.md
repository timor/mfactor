# design notes
- non-portable-byte-code interpreter, although mnemonics are portable
- position-independent when using base-relative addressing (stdlib only supports base-relative)
- the tradeoff wether to create a new word rather than using a macro (inline quotation)
  starts at 4 primitive instructions on 32-bit machines, and 8 primitive instructions on 64 bit machines, respectively
- cstrings are null-terminated (remove!)

## definitions ##
- cell: datatype used on parameter stack, must be able to hold a pointer
- inst: byte code instruction used in program flow
- base-relative: short holding an offset pointer relative to base (like segment addressing)

# code layout #
- byte code, inline-data must be prefixed by corresponding literal preserving words (calls, lits, ...)
- byte code words are distinguished by address when used on the stack,
  i.e. when address would point into inaccessible memory, it must be a
  primitive instruction

# stacks #

## data stack ##

## catch stack ##
- exception handling records (continuations)

## retain stack ##
- general purpose stack
- must be empty after word exits (TODO: include balance checks in parser)

## return stack ##
- saves return information as well as beginning of word information for debugging
