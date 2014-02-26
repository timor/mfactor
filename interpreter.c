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

	#if TRACE_INTERPRETER
		#define IFTRACE(expr) expr
	#else
		#define IFTRACE(expr)
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

/* empty ascending stack */
	#define push(sp,val) (*sp=val,sp++)
	#define pop(sp) ({sp--;*sp;})
	#define peek_n(sp,nth) (*(sp-nth))
	#define drop_n(sp,num) (sp-=num)

/* dictionary grows up*/
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
	DICT("\"",strstart),
	DICT("if",TBEGIN(ifquot)),
	DICT("square",TBEGIN(square)),
};

const inst const square[]={retsub,mul,dup};
const inst const ifquot[]={retsub,call,truefalse};
const inst const unknown_token[]={retsub,emit,FIXNUM('X'),lit,emit,FIXNUM('_'),lit,emit,FIXNUM('X'),lit};

static inst* find_by_name(char *fname)
{
IFTRACE(printf("looking for '%s' ", fname));
	for(dict_entry* ptr=dict;ptr < dict+sizeof(dict);ptr+=ptr->name_length+2*sizeof(void*)){
	if (strcmp(fname,ptr->name)==0) {
	IFTRACE(printf("found at: %#x\n",(cell)ptr->address));
	return ptr->address;
	} }
IFTRACE(printf("not found\n"));
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
		IFTRACE(printstack(psp,pstack));
		IFTRACE(printstack(rsp,rstack));
		i= (*pc--);
		if (i >= INSTBASE) {          /* valid bytecode instruction */
			IFTRACE(printf("i:%#x\n",i));
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
			case call:
				push(rsp,(cell)pc);
				pc=(inst*)pop(psp);
				goto next; break;
			default:
				printf("undefined instruction %x\n",*pc);
				return;
			}
		} else {                    /* memory, call thread  */
			inst * skipped = (inst *)pc-(sizeof(void *)-1); /* adjust skip over memory address */
			inst * next_word = *(inst **)(skipped+1); /* TODO platform-dependent */
			IFTRACE(printf("w:%#x\n",(cell)next_word));
			push(rsp,(cell)skipped);
			pc=next_word;
		}
	}
}

#endif
