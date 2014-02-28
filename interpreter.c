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
	void * address;					/* pointer into memory */
	length name_length;
	char name[];
}	__attribute__((packed)) dict_entry;
/* TODO: doc quirk that primitive names are null-terminated */

typedef struct return_entry {
	inst * return_address;
	inst * current_call;
} return_entry;

/* dictionary grows up*/
	#define DICT(wname,addr)	{.address=(void *)addr,.name=wname,.name_length=sizeof(wname)}
	#define PDICT(wname,addr) DICT(wname, ((intptr_t)addr << (8*(sizeof(inst*)-sizeof(inst)))))
#define TDICT(wname,word) DICT(wname,TBEGIN(word))
dict_entry dict[VM_DICT] __attribute__((aligned(1))) = {
	PDICT("dup",dup),
	PDICT("drop",drop),
	PDICT(".",pprint),
	PDICT("+",add),
	PDICT("*",mul),
	PDICT("0",zero),
	PDICT("1",one),
	PDICT("2",two),
	/* PDICT("}",lend), */
	PDICT("{",input_list),
	PDICT("[",input_quot),
	/* PDICT("]",qend), */
	PDICT("neg",neg),
	PDICT("-",sub),
	PDICT("?",truefalse),
	PDICT("allot",allot),
	PDICT("recurse",recurse),
	PDICT("\"",input_str),
	PDICT("st",stack_show),
	PDICT("shift",asl),
	PDICT("/",div),
	PDICT("mod",mod),
	PDICT("swap",swap),
	PDICT("set",set),
	PDICT("get",get),
	PDICT("bitand",bitand),
	PDICT("bitor",bitor),
	PDICT("bitxor",bitxor),
	PDICT("bitnot",bitnot),
	TDICT("if",ifquot),
	TDICT("square",square),
};

const inst const square[]={retsub,mul,dup};
/* (cond [true ...] [false ...] -- ... ) */
const inst const ifquot[]={retsub,call,truefalse};
/* ( trash -- )  */
const inst const display_notfound[]={retsub,emit,'\n', litbyte, emit,'X',litbyte,emit,'_',litbyte,emit,'X',litbyte, drop};
/* ( addr -- bool )  */

/* returns same address again if not found*/
static inst* find_by_name(char *fname)
{
  IFTRACE1(printf("looking for '%s' ", fname));
  for(char * ptr=(char*)dict;
		(ptr < ((char*)dict+sizeof(dict)))&&(((dict_entry*)ptr)->name_length > 0);
		ptr += (((dict_entry*)ptr)->name_length + sizeof(length) + sizeof(void*))) {
	 dict_entry *dptr = (dict_entry*)ptr;
	 IFTRACE1(printf("comparing to (%#x)%s",(intptr_t)dptr->name,dptr->name));
	 if (strcmp(fname,dptr->name)==0) {
		IFTRACE1(printf("found at: %#x\n",(cell)dptr->address));
		return dptr->address;
	 }
  }
  IFTRACE1(printf("not found\n"));
  return (inst *) NULL;
}

	static bool parse_number(char *str, cell * number){
		int num;
		IFTRACE1(printf("trying to read '%s' as number...",str));
		unsigned int read = sscanf(str,"%i",&num);
		if (read == 1) {
			IFTRACE1(printf("got %d\n",num));
			*number=(cell)num;
			return true;
		} else {
			IFTRACE1(printf("failed\n"));
			return false;
		}
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
static void print_return_stack(return_entry * sp, return_entry * stack)
{
	printf("stack:");
	for(return_entry* ptr = sp-1;ptr >= stack;ptr--)
		{
			printf(" {%#x->%#x}",(intptr_t)ptr->current_call,(intptr_t)ptr->return_address);
		}
	printf("\n");
}


enum nesting_type {
	nesting_quot,
	nesting_list
};

/* skip over instruction stream until a certain one */
/* TODO: support nesting, since this is akin to quoting */
static inst * skip_instruction(inst* pc,inst until){
	inst *ptr=pc;
	for(inst i= *ptr; i != until; i=*(--ptr)) {
		IFTRACE2(printf("skipping over %#x, ",i));
		if (i < INSTBASE)
			ptr-=(sizeof(inst*)-1);
	}
	IFTRACE2(printf("skipped until %#x\n",(intptr_t)ptr));
	return ptr;
}

static void error(char * str)
{
  printf("error: ");
  printf(str);
  printf("\n");
}

#define assert_pop(sp,min) if (sp <= min) { error("stack underflow");return;}
#define assert_push(sp,min,size) if (sp > min+size){ error("stack overflow");return;}
  

/* empty ascending stack */
	#define push_(sp,val) *sp=val;sp++;
	#define pop_(sp) --sp;*sp;
#define ppush(val) ({assert_push(psp,pstack,VM_PSTACK);push_(psp,val)})
#define ppop() ({assert_pop(psp,pstack);pop_(psp)})
#define returnpush(val) ({assert_push(returnsp,returnstack,VM_RETURNSTACK);push_(returnsp,val)})
#define returnpop() ({assert_pop(returnsp,returnstack);pop_(returnsp)})
#define retainpush(val) ({assert_push(retainsp,retainstack,VM_RETAINSTACK);push_(retainsp,val)})
#define retainpop() ({assert_pop(retainsp,retainstack);pop_(retainsp)})

	#define peek_n(sp,nth) (*(sp-nth))

static cell memory[VM_MEM];

void interpreter(inst * user_program)
{
	/* parameter stack */
	static cell pstack[VM_PSTACK]={0};
	static cell* psp = &pstack[0];
	/* return stack, not preserved across calls */
	return_entry returnstack[VM_RETURNSTACK]={{0}};
	return_entry* returnsp = &returnstack[0];
	/* retain stack */
	static cell retainstack[VM_RETAINSTACK]={0};
	static cell* retainsp =&retainstack[0];
	/* catch stack */
	/* static cell cstack[VM_CSTACK]={0}; */
	/* static cell* csp = &cstack[0]; */
	/* TODO: name stack */
	static cell* CP=memory;
	cell x;								/* temporary value for operations */
	inst unknown_token[]={retsub, CALL(ifquot), CALL(display_notfound), lit, PCALL(nop), lit, parsenum};
	inst program[]={quit, CALL(ifquot), CALL(unknown_token), lit, PCALL(call), lit, find, token };
	inst *pc = user_program ? : &program[sizeof(program)/sizeof(inst)-1];
	return_entry start_entry = {.return_address=NULL,.current_call = pc};
	returnpush(start_entry);

	while(1) {
		inst i;
	next:
		IFTRACE2(printstack(psp,pstack));
		IFTRACE2(printstack(retainsp,retainstack));
		IFTRACE2(print_return_stack(returnsp,returnstack));
		i= (*pc--);
		if (i >= INSTBASE) {				/* valid bytecode instruction */
			dispatch:
			IFTRACE2(printf("i:%#x\n",i));
			switch (i) {
#define UNOP(op) { x=(op (ppop())); ppush(x);} break
#define BINOP(op) { x = ppop(); cell y = ppop(); ppush(y op x);} break
			case drop: ppop(); break;
			case zero: ppush(0); break;
			case one: ppush(1); break;
			case two: ppush(2); break;
			case add: BINOP(+);
			case mul: BINOP(*);
			case sub: BINOP(-);
			case neg: UNOP(-);
			case asl: BINOP(<<);
			case div: BINOP(/);
			case mod: BINOP(%);
			case bitand: BINOP(&);
			case bitor: BINOP(|);
			case bitxor: BINOP(^);
			case bitnot: UNOP(~);
			case dup:
				ppush(peek_n(psp,1)); break;
			case code_ptr:
				ppush((cell)&CP);
				break;
			case ref:					  /* only gc knows a difference */
			case lit: {
				cell y=*((cell*)(pc-(sizeof(cell)-sizeof(inst))));
				ppush(y);
				pc-=sizeof(cell);
			} break;
			case litbyte:
				x=(cell)(*(pc--));
				ppush(x);
				break;
			case pprint:
printf("%#x",ppop());
break;
			case emit:
				putchar(ppop());
				fflush(stdout);			/* TODO remove eventually */
				break;
			case receive:
				ppush(getchar()); break;
			case name:
			case quit:
				printf("bye!\n");
				return;
 case qend:
 case retsub: {
	 return_entry e = returnpop();
	 pc=e.return_address;
 } break;
			case eql: BINOP(==);
			case swap: {
				x=ppop();
				cell y = ppop();
				ppush(x);
				ppush(y);
			} break;
			case to_r:
				retainpush(ppop());break;
			case r_from:
				ppush(retainpop());break;
			/* ( cond true false -- true/false ) */
			case truefalse:			  /* this one assumes the most about the stack right now */
				{
					cell false_cons = ppop();
					cell true_cons = ppop();
					cell cond = ppop();
					ppush(cond ? true_cons : false_cons);
				} break;
			case token: {
				char *tok = read_token();
				if (tok) {
					ppush((cell)tok);
				} else {
					error("token reader error");
					return;
				}} break;
				/* (str -- foundp addr) */
			case find: {
				cell orig=ppop();
				inst * addr=find_by_name((char*)orig);
				ppush(addr==NULL ? orig : (cell)addr);
				ppush(addr==NULL ? false : true);
			}
				break;
			case call: {
				/* check if call is primitive, if yes, substitute execution, since call only
					applies to quotations */
				cell quot = ppop();
				if (quot >= INSTBASE_CELL) {
					IFTRACE2(printf("calling prim\n"));
					i=(quot>>(8*(sizeof(inst*)-sizeof(inst))));
					goto dispatch;
				} else {
					IFTRACE2(printf("calling inmem word\n"));
					return_entry e = {.return_address = pc, .current_call=(inst*) quot};
					returnpush(e);
					pc=(inst *)quot;
					goto next;
				}} break;
				case stack_show:
				  printf("\np");
				  printstack(psp,pstack);
				  printf("retain");
				  printstack(retainsp,retainstack);
				  printf("return");
				  print_return_stack(returnsp,returnstack);
				  break;
				/* case tuck: { */
			/* 	x= pop(psp); */
			/* 	cell y= pop(psp); */
			/* 	push(psp,x); */
			/* 	push(psp,y); */
			/* 	push(psp,x); */
			/* } */

			/* (str -- num/str bool) */
			case parsenum: {
				char *str = (char *)ppop();
				cell num = 0xa5a5a5a5;
				bool success=parse_number(str,&num);
				ppush(success ? num : (cell) str);
				ppush((cell)success);
			} break;
			case nop:
			break;
/* ( value address -- ) */
			case set:
				x=ppop();
				*((cell*)x)=(ppop());
				break;
			 case get:
				x = *((cell *)(ppop()));
				ppush(x);
				break;
				/* skip over to end of quotation , leave starting address on parameter stack*/
			case qstart:
				IFTRACE2(printf("qstart saving #%x\n",(intptr_t)pc));
				ppush((cell)pc);
				pc=skip_instruction(pc,qend);
				pc-=1;
				break;
 case recurse:
			pc=(returnsp-1)->current_call;
break;
			default:
				printf("unimplemented instruction %#x\n",i);
				return;
			}
		} else {							 /* memory, call thread	 */
			inst * skipped = (inst *)pc-(sizeof(void *)-1); /* adjust skip over memory address */
			inst * next_word = *(inst **)(skipped+1); /* TODO platform-dependent */
			IFTRACE2(printf("w:%#x\n",(cell)next_word));
			return_entry e = {.return_address = skipped, .current_call=next_word};
			returnpush(e);
			pc=next_word;
		}
	}
}

#endif
