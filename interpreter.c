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

/* for storing the length of a stack item, note that this is ONLY for the stack, not for in-memory data */
typedef unsigned char length;

/* entry in name dictionary */
/* TODO: ensure correct scanning direction so that skipping over entries stays trivial */
typedef struct dict_entry
{
  void * address;               /* pointer into memory */
  length name_length;
  unsigned char name[];
} dict_entry;
/* TODO: doc quirk that primitive names are null-terminated */

/* empty ascending stack */
#define push(sp,val) (*sp=val,sp++)
#define pop(sp) (sp--,*sp)
#define peek_n(sp,nth) (*(sp-nth))
#define drop_n(sp,num) (sp-=num)

#define DICT(wname,addr)   {.address=(void *)addr,.name=wname,.name_length=sizeof(wname)}
dict_entry dict[VM_DICT]={
  DICT("dup",dup),
  DICT("drop",drop),
  DICT("+",add),
  DICT("*",mul),
  DICT("}",lend),
  DICT("{",lstart),
  DICT("[",qstart),
  DICT("]",qend),
  DICT("neg",neg),
  DICT("-",sub),
  DICT("?",truefalse),
  DICT("allot",allot),
  DICT("if",TBEGIN(ifquot)),
  DICT("square",TBEGIN(square)),
};

const inst const square[]={retsub,mul,dup};
const inst const ifquot[]={retsub,call,truefalse};

void interpreter(inst * user_program)
{
  /* parameter stack */
  static cell pstack[VM_PSTACK]={0};
  static cell* psp = &pstack[0];
  /* retain / compile control stack */
  static cell rstack[VM_RSTACK]={0};
  static cell* rsp = &rstack[0];
  /* catch stack */
  static cell cstack[VM_CSTACK]={0};
  static cell* csp = &cstack[0];
  /* TODO: name stack */
  cell x;                       /* temporary value for operations */
  inst program[]={quit,emit,CALL(square),add,dup,mul,dup,two};
  inst *pc = user_program ? : &program[sizeof(program)/sizeof(inst)-1];

  while(1) {
    inst i;
  next:
    i= (*pc--);
    if (i >= INSTBASE) {          /* valid bytecode instruction */
      switch (i) {
#define UNOP(op) { push(psp,(op (pop(psp))));} break
#define BINOP(op) { x = pop(psp); push(psp,(pop(psp) op x));} break
      case drop: drop_n(psp,1); break;
      case zero: push(psp,0); break;
      case one: push(psp,1); break;
      case two: push(psp,2); break;
      case add: BINOP(+);
      case mul: BINOP(*);
      case sub: BINOP(-);
      case neg: UNOP(-);
      case dup: 
        push(psp, peek_n(psp,1)); break;
      case ref:                 /* only gc knows a difference */
      case lit: {
        cell y=*((cell*)(pc-(sizeof(cell)-sizeof(inst))));
        push(psp,y);
        pc-=sizeof(cell);
      } break;
      case emit:
        putchar(pop(psp));
        fflush(stdout);         /* TODO remove eventually */
        break;
      case receive:
        push(psp,getchar()); break;
      case name:
      case quit:
        printf("bye!\n");
        return;
      case retsub:
        pc=(inst*) pop(rsp); break;
      case eql: BINOP(==);
      case swap: {
        x=pop(psp);
        cell y = pop(psp);
        push(psp,x);
        push(psp,y);
      } break;
      case to_r:
        push(rsp,pop(psp));break;
      case r_from:
        push(psp,pop(rsp));break;
      case truefalse:           /* this one assumes the most about the stack right now */
      {
        cell false_cons = pop(psp);
        cell true_cons = pop(psp);
        cell cond = pop(psp);
        push(psp,cond ? true_cons : false_cons);
      } break;
      case call:
        push(rsp,(cell)pc);
        pc=(inst*)pop(psp);
        goto next; break;
      default:
        printf("undefined instruction %d\n",*pc);
        return;
      }
    } else {                    /* memory, call thread  */
      inst * skipped = (inst *)pc-(sizeof(void *)-1); /* adjust skip over memory address */
      inst * next_word = *(inst **)(skipped+1); /* TODO platform-dependent */
      push(rsp,(cell)skipped);
      pc=next_word;
    }
  }
}

#endif
