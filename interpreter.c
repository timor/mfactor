/*****************************************************************************
 *
 *
 ******************************************************************************
 *
 * File Name: interpreter.c
 *
 * Created: 2014-02-19 15:34
 *
 * Author: timor <timor.dd@googlemail.com>
 *
 * Description: interpreter for easier debugging
 *****************************************************************************/

#ifdef __GNUC__

#include "interpreter.h"
#include <string.h>
#include <stddef.h>
#include <stdio.h>
#include <stdint.h>

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
#warning "defining INSTBASE for x64!"
#define INSTBASE 0x80
#endif

/* primitive instruction set */
enum inst_code {
  dup=INSTBASE,                     /* starting value architecture dependent!!! */
  rot, drop, zero, one, two, add, mul, neg, sub, emit, claim, to_r, r_from, lit, type,
  name, exit,
  quit
};

typedef unsigned char inst;     /* it's byte code after all */

typedef enum cell_type
{
  cell_fixnum = 0,
  cell_sequence,
  cell_string,					  /* value is number of chars following */
  cell_bignum,
  cell_code,
  cell_symbol,
  cell_typecell                 /* meta!(for introspection) */
} cell_type;

typedef struct cell
{
  unsigned int value:29;
  cell_type type:3;
} cell;

/* somehow the following doesnt count as constant value for static initializer purposes */
#define FIXNUM(c) ((cell) {.type=cell_fixnum,.value=c})
#define TYPECELL(c) ((cell) {.type=cell_typecell,.value=c})
  

typedef struct dict_entry
{
  void * address;               /* pointer into memory */
  cell name;						  /* a cell_string */
} dict_entry;

/* empty ascending stack */
#define push(sp,val) (*(sp++)=val)
#define pop(sp) (*(--sp))
#define peek(sp) (*(sp-1))

static void push_mem(cell *from, cell *to, cell *sp)
{
  ptrdiff_t diff = (to-from)*sizeof(cell);
  if (diff>0)
    memcpy(sp,from,diff);
  else
    memcpy(sp-diff,to,-diff);
}

union wide_cell 
{
  cell cell;
  inst * address;
} wide_cell;

inst square[]={exit,mul,dup};

void interpreter()
{
  cell pstack[VM_PSTACK]={0};
  cell* psp = &pstack[0];
  union wide_cell rstack[VM_RSTACK]={0};
  union wide_cell* rsp = &rstack[0];
  cell cstack[VM_CSTACK]={0};
  cell* csp = &cstack[0];
  

#define next goto **(--pc)
#define UNOP(op) { x = pop(psp); x.value=(op x.value); push(psp,x);} break
#define BINOP(op) { x = pop(psp); x.value=(pop(psp).value op x.value); push(psp,x);} break
#define TBEGIN(word) (intptr_t)&word[sizeof(word)/sizeof(inst)-1]
#define CALL64(word) (word>>0)&0xff,(word>>8)&0xff,(word>>16)&0xff,(word>>24)&0xff,(word>>32)&0xff,(word>>40)&0xff,(word>>48)&0xff,(word>>56)&0xff
#define CALL(thread) CALL64(TBEGIN(thread))
  
  cell x;
  inst program[]={quit,emit,CALL(square),add,dup,mul,dup,two};
  inst *pc = &program[sizeof(program)/sizeof(inst)-1];


  while(1) {
    inst i = (*pc--);
    if (i & INSTBASE) {          /* valid bytecode instruction */
      switch (i) {
      case drop:
        x = pop(psp);
        if (x.type != cell_fixnum)
          for (int i = 0; i < x.value; i++)
            (void) pop(psp);
        break;
      case zero: push(psp,FIXNUM(0)); break;
      case one: push(psp,FIXNUM(1)); break;
      case two: push(psp,FIXNUM(2)); break;
      case add: BINOP(+);
      case mul: BINOP(*);
      case sub: BINOP(-);
      case neg: UNOP(-);
      case dup:
        x = peek(psp);
        if (x.type == cell_fixnum)
          push(psp, x);
        else
          push_mem(psp-(x.value+1),psp,psp);
        break;
      case lit:
        push(psp,*((cell*)++pc));
        break;
      case emit:
        putchar(pop(psp).value);
        fflush(stdout);
        break;
      case type:
        push(psp,TYPECELL(pop(psp).type));
      case name:
      case quit:
        printf("bye!\n");
        return;
      case exit:
        pc=pop(rsp).address; break;
      default:
        printf("unknown instruction %d\n",*pc);
        return;
      }
    } else {                    /* memory, call thread  */
      inst * address = *(inst *)pc; /* TODO fix warning */
      push(rsp,((union wide_cell) pc));
      pc=address;
    }
  }
}

#endif
