
#ifndef INTERPRETER_H
#define INTERPRETER_H

#include <stdbool.h>
#include <stdint.h>
#include "generated/image_size.h"

typedef unsigned char inst;
typedef unsigned short short_jump_target;  /* relative jumps in 64k on 32 bit */
typedef uintptr_t jump_target;  /* long absolute jump */
typedef uintptr_t cell;                 /* memory cell must at least hold pointer */
/* inst * image; */
/* data memory (affects non-transient data) in cells*/
#ifndef VM_MEM
 #define VM_MEM 256
#endif

/* dictionary size (affects number of named items)*/
#ifndef VM_DICT
 #define VM_DICT 512
#endif

/* parameter stack size (affects transient data)*/
#ifndef VM_PSTACK
 #define VM_PSTACK 64
#endif

/* return stack size (affects nesting of functions)*/
#ifndef VM_RETURNSTACK
 #define VM_RETURNSTACK 64
#endif

/* retain stack size (affects maximum amount of postponing data use) */
#ifndef VM_RETAINSTACK
 #define VM_RETAINSTACK 32
#endif
#ifndef INSTBASE
 #if (__linux && __LP64__)
  #define INSTBASE 0x80U
 #elif (CORTEX_M)
  #define INSTBASE 0xA0U
 #else
  #error "don't know instruction code base for architecure!"
 #endif
#endif
#define INSTBASE_CELL ((cell)INSTBASE<<(8*(sizeof(inst *)-sizeof(inst))))
void interpreter(short_jump_target);

#endif
