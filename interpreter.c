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
	#include "reader.h"
	#include <string.h>
	#include <stddef.h>
	#include <stdio.h>
	#include <stdbool.h>

	#if TRACE_INTERPRETER >= 1
		#define IFTRACE1(expr) expr
	#else
		#define IFTRACE1(expr)
	#endif
#if TRACE_INTERPRETER >= 2
#define IFTRACE2(expr) expr
#else
#define IFTRACE2(expr)
#endif

/* for storing the length of a stack item, note that this is ONLY for the stack, not for in-memory data */
typedef unsigned char length;

/* entry in name dictionary */
/* TODO: ensure correct scanning direction so that skipping over entries stays trivial */
typedef struct dict_entry
{
	void * address;               /* pointer into memory */
	length name_length;
	char name[];
} dict_entry;
/* TODO: doc quirk that primitive names are null-terminated */

/* dictionary grows up*/
	#define DICT(wname,addr)   {.address=(void *)addr,.name=wname,.name_length=sizeof(wname)}
	#define PDICT(wname,addr) DICT(wname, ((intptr_t)addr << (8*(sizeof(inst*)-sizeof(inst)))))
dict_entry dict[VM_DICT]={
	PDICT("dup",dup),
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
	DICT("\"",strstart),
	DICT("if",TBEGIN(ifquot)),
	DICT("square",TBEGIN(square)),
    PDICT("st",stack_show),
};

const inst const square[]={retsub,mul,dup};
const inst const ifquot[]={retsub,call,truefalse};
const inst const unknown_token[]={retsub,emit,FIXNUM('X'),lit,emit,FIXNUM('_'),lit,emit,FIXNUM('X'),lit};

static inst* find_by_name(char *fname)
{
  IFTRACE1(printf("looking for '%s' ", fname));
  for(char * ptr=(char*)dict;
      ptr < ((char*)dict+sizeof(dict));
      ptr += (((dict_entry*)ptr)->name_length + sizeof(length) + sizeof(void*))) {
    dict_entry *dptr = (dict_entry*)ptr;
    IFTRACE1(printf("comparing to (%#x)%s",dptr->name,dptr->name));
    if (strcmp(fname,dptr->name)==0) {
      IFTRACE1(printf("found at: %#x\n",(cell)dptr->address));
      return dptr->address;
    } 
  }
  IFTRACE1(printf("not found\n"));
  return NULL;
}

static void printstack(cell * sp, cell * stack)
{
	printf("stack:");
	for(cell* ptr = sp-1;ptr >= stack;ptr--)
		{
			printf(" %#x",*ptr);
		}
	printf("\n");
}


enum nesting_type {
	nesting_quot,
	nesting_list
};

static void error(void)
{
	printf("error\n");
}

/* empty ascending stack */
	#define push(sp,val) ({*sp=val;sp++;})
	#define pop(sp) ({--sp;*sp;})
	#define peek_n(sp,nth) (*(sp-nth))
	#define drop_n(sp,num) (sp-=num)

void interpreter(inst * user_program)
{
	/* parameter stack */
	static cell pstack[VM_PSTACK]={0};
	static cell* psp = &pstack[0];
	/* retain / compile control stack */
	static cell rstack[VM_RSTACK]={0};
	static cell* rsp = &rstack[0];
	/* catch stack */
	/* static cell cstack[VM_CSTACK]={0}; */
	/* static cell* csp = &cstack[0]; */
	/* TODO: name stack */
	cell x;                       /* temporary value for operations */
	inst program[]={quit, CALL(ifquot), CALL(unknown_token), lit, find, token };
	inst *pc = user_program ? : &program[sizeof(program)/sizeof(inst)-1];

	while(1) {
		inst i;
	next:
		IFTRACE2(printstack(psp,pstack));
		IFTRACE2(printstack(rsp,rstack));
		i= (*pc--);
		if (i >= INSTBASE) {          /* valid bytecode instruction */
			dispatch:
			IFTRACE2(printf("i:%#x\n",i));
			switch (i) {
#define UNOP(op) { x=(op (pop(psp))); push(psp,x);} break
#define BINOP(op) { x = pop(psp); cell y = pop(psp); push(psp, x op y);} break
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
			case token: {
				char *tok = read_token();
				if (tok) {
					push(psp,(cell)tok);
				} else {
					error();
					return;
				}} break;
			case find: {
				inst * addr=find_by_name((char*)pop(psp));
				push(psp,addr==NULL ? false : true);
				push(psp,(cell)addr);
			}
				break;
			case call: {
				/* check if call is primitive, if yes, substitute execution, since call only
					applies to quotations */
				cell quot = pop(psp);
				if (quot >= INSTBASE_CELL) {
					IFTRACE2(printf("calling prim\n"));
					i=(quot>>(8*(sizeof(inst*)-sizeof(inst))));
					goto dispatch;
				} else {
					IFTRACE2(printf("calling inmem word\n"));
					push(rsp,(cell)pc);
					pc=(inst *)quot;
					goto next;
				}} break;
            case stack_show:
              printf("\np");
              printstack(psp,pstack);
              printf("r");
              printstack(rsp,rstack);
              break;
			default:
				printf("unimplemented instruction %#x\n",*pc);
				return;
			}
		} else {                    /* memory, call thread  */
			inst * skipped = (inst *)pc-(sizeof(void *)-1); /* adjust skip over memory address */
			inst * next_word = *(inst **)(skipped+1); /* TODO platform-dependent */
			IFTRACE2(printf("w:%#x\n",(cell)next_word));
			push(rsp,(cell)skipped);
			pc=next_word;
		}
	}
}

#endif
