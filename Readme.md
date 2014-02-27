# design notes
- not designed as a portable byte code interpreter, code will not be position independent
- the tradeoff wether to create a new word rather than using a macro
  starts at 4 primitive instructions on 32-bit machines, and 8 primitive instructions on 64 bit machines, respectively
- strings are null-terminated

## definitions ##
- cell: datatype used on parameter stack, must be able to hold a pointer
- inst: byte code instruction used in program flow

# code layout #
- byte code, intermixed with memory addresses
- memory addresses point to threads
- byte code words are distinguished by address, e.g. if the MSByte would
  point into inaccessible memory, it must be an instruction
- since the MSByte must be read first to decide wether to call a
  byte instruction or a memory address, little endian machines define
  their code "backwards" in memory physically

# stacks #

## data stack ##

## catch stack ##
- exception handling records

## retain stack ##
- used for controlling nested sequence acquisition during entry
- note that this means that input mode can be determined by looking at
  how many items are on the retain stack during input

## return stack ##
- saves return information as well as beginning of word information for tail recursion in interpreter mode
