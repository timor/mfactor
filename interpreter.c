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
#include <stdbool.h>

typedef struct dict_entry
{
  void * address;               /* pointer into memory */
  cell name;						  /* a cell_string */
} dict_entry;

/* empty ascending stack */
#define push(sp,val) (*(sp++)=val)
#define pop(sp) (*(--sp))
#define peek(sp) (*(sp-1))
#define drop_n(sp,num) (sp-=num)

static void push_mem(cell *from, cell *to, cell *sp)
{
  ptrdiff_t diff = (to-from)*sizeof(cell);
  if (diff>0)
    memcpy(sp,from,diff);
  else
    memcpy(sp-diff,to,-diff);
}

typedef union wide_cell 
{
  inst * address;
  cell cell;
} wide_cell;

#define UNOP(op) { x = pop(psp); x.value=(op x.value); push(psp,x);} break
#define BINOP(op) { x = pop(psp); x.value=(pop(psp).value op x.value); push(psp,x);} break

inst square[]={endsub,mul,dup};

void interpreter(inst * user_program)
{
  /* parameter stack */
  static cell pstack[VM_PSTACK]={0};
  static cell* psp = &pstack[0];
  /* retain / compile control stack */
  static wide_cell rstack[VM_RSTACK]={0};
  static wide_cell* rsp = &rstack[0];
  /* catch stack */
  static cell cstack[VM_CSTACK]={0};
  static cell* csp = &cstack[0];
  /* TODO: name stack */
  cell x;                       /* temporary value for operations */
  inst program[]={quit,emit,CALL(square),add,dup,mul,dup,two};
  inst *pc = user_program ? : &program[sizeof(program)/sizeof(inst)-1];

  while(1) {
    inst i = (*pc--);
    if (i >= INSTBASE) {          /* valid bytecode instruction */
    dispatch:
      switch (i) {
      case drop:
        x = pop(psp);
        if (x.sequencep)
          drop_n(psp,x.length);
        break;
      case zero: push(psp,SCALAR(0)); break;
      case one: push(psp,SCALAR(1)); break;
      case two: push(psp,SCALAR(2)); break;
      case add: BINOP(+);
      case mul: BINOP(*);
      case sub: BINOP(-);
      case neg: UNOP(-);
      case dup:
        x = peek(psp);
        if (!x.sequencep)
          push(psp, x);
        else
          push_mem(psp-(x.length+1),psp,psp);
        break;
      case lit: {
        cell y=*((cell*)(pc-(sizeof(cell)-sizeof(inst))));
        push(psp,y);
        pc-=sizeof(cell);
      } break;
      case emit:
        putchar(pop(psp).value);
        fflush(stdout);
        break;
      case receive:
        push(psp,SCALAR(getchar())); break;
      /* case type: */
      /*   push(psp,TYPECELL(pop(psp).type)); */
      case name:
      case quit:
        printf("bye!\n");
        return;
      case endsub:
        pc=pop(rsp).address; break;
      case eql:
        x=pop(psp);
        x.value=(x.value==pop(psp).value);
        push(psp,(x)); break;
      case to_r:
        push(rsp,(wide_cell)pop(psp));break;
      case r_from:
        push(psp,pop(rsp).cell);break;
      default:
        printf("undefined instruction %d\n",*pc);
        return;
      }
    } else {                    /* memory, call thread  */
      inst * skipped = (inst *)pc-(sizeof(void *)-1); /* adjust skip over memory address */
      inst * next_word = *(inst **)(skipped+1); /* TODO platform-dependent */
      push(rsp,((wide_cell) skipped));
      pc=next_word;
    }
  }
}

#endif
