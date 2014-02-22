#ifndef INTERPRETER_H
#define INTERPRETER_H

#include <stdbool.h>
#include <stdint.h>


typedef unsigned char inst;     /* it's byte code after all */

#ifndef VM_DICT
#define VM_DICT 8192
#endif
#ifndef VM_PSTACK
#define VM_PSTACK 256
#endif
#ifndef VM_RSTACK
#define VM_RSTACK 64
#endif
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
  rot, drop, zero, one, two, add, mul, neg, sub, emit, receive, to_r, r_from, lit, type,
  name, endsub,
  quit
};


typedef union cell
{
  struct {
    unsigned int length:31;
    bool sequencep:1;
  };
  struct {
    int value:31;
    bool ____dummy1oneone:1;
  };
} cell;

/* somehow the following doesnt count as constant value for static initializer purposes */
#define SCALAR(c) ((cell) {.sequencep=false,.value=c})


void interpreter(inst *);

#define TBEGIN(word) (intptr_t)&word[sizeof(word)/sizeof(inst)-1]
#define CALL64(word) (word>>0)&0xff,(word>>8)&0xff,(word>>16)&0xff,(word>>24)&0xff,(word>>32)&0xff,(word>>40)&0xff,(word>>48)&0xff,(word>>56)&0xff
#define CALL32(word) (word>>0)&0xff,(word>>8)&0xff,(word>>16)&0xff,(word>>24)&0xff
#if (__SIZEOF_POINTER__ == 4)
#define CALL(thread) CALL32(TBEGIN(thread))
#elif (__SIZEOF_POINTER__ == 8)
#define CALL(thread) CALL64(TBEGIN(thread))
#else
#error "size of pointer unkown"
#endif

/* on 32 bit cell size architecture: */
#define FIXNUM(x) CALL32(SCALAR(x).value)

#endif
