#ifndef INTERPRETER_H
#define INTERPRETER_H

#include <stdbool.h>
#include <stdint.h>


typedef unsigned char inst;     /* it's byte code after all */

/* data memory (affects non-transient data)*/
#ifndef VM_MEM
#define VM_MEM 8192
#endif
/* dictionary size (affects number of named items)*/
#ifndef VM_DICT
#define VM_DICT 1024
#endif
/* parameter stack size (affects transient data)*/
#ifndef VM_PSTACK
#define VM_PSTACK 256
#endif
/* retain stack size (affects nesting of functions)*/
#ifndef VM_RSTACK
#define VM_RSTACK 64
#endif
/* catch stack size (affects nesting of exception handlers)*/
#ifndef VM_CSTACK
#define VM_CSTACK 64
#endif

/* extern int putchar(int); */
/* extern int getchar(int); */
#ifndef INSTBASE
#if (__linux && __LP64__)
#define INSTBASE 0x80
#elif (CPU_LPC4337)             /* all cortexes, actually */
#define INSTBASE 0xA0
#else
#error "don't know instruction code base for architecure!"
#endif
#endif

/* primitive instruction set */
enum inst_set {
  dup=INSTBASE,                     /* starting value architecture dependent!!! */
  eql,
  rot, drop, zero, one, two, add, mul, neg, sub, emit, receive, to_r, r_from, lit,
  name, qstart, qend, lstart, lend, retsub, truefalse, call, ref,
  quit
};

const inst const square[3];
const inst const ifquot[3];

typedef intptr_t cell;

void interpreter(inst *);

#define TBEGIN(word) (intptr_t)&word[sizeof(word)/sizeof(inst)-1]
#define CELL64(word) (word>>0)&0xff,(word>>8)&0xff,(word>>16)&0xff,(word>>24)&0xff,(word>>32)&0xff,(word>>40)&0xff,(word>>48)&0xff,(word>>56)&0xff
#define CELL32(word) (word>>0)&0xff,(word>>8)&0xff,(word>>16)&0xff,(word>>24)&0xff
#if (__SIZEOF_POINTER__ == 4)
#define CELL(word) CELL32(word)
#elif (__SIZEOF_POINTER__ == 8)
#define CELL(word) CELL64(word)
#else
#error "size of pointer unkown"
#endif

#define CALL(thread) CELL(TBEGIN(thread))
/* breaks down scalar value for insertion into byte code stream */
#define FIXNUM(x) CELL(x)

#endif
