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

/* these are available after mfactor task has run */
	#include "generated/bytecode.h"
	#include "generated/inst_enum.h"

/* target specific stuff */
	#include "runtime.h"
	#include "reset_system.h"

	#include "seq_headers.h"

/* global array of special variables:
	0: MP - memory write pointer
	1: HANDLER - handler frame location in r(etain) stack (dynamic chain for catch frames)
	2: DEBUG_LEVEL - 0 to turn off, increasing will produce more verbose debug output
	3: RESTART - word where to restart when hard error occured
	4: STEP_HANDLER - address of handler which can be used for single stepping
	5: BASE - address of current 64k segment base
	6: OUTPUT_STREAM: 1: stdout, 2: stderr
	has occured */
	#define _NumSpecials 10
static const unsigned char NumSpecials = _NumSpecials;
static cell special_vars[_NumSpecials];
	#define MP special_vars[0]
	#define HANDLER special_vars[1]
	#define DEBUG_LEVEL special_vars[2]
	#define BASE special_vars[5]
	#define OUTPUT_STREAM special_vars[6]

#define STDOUT 1					  /* not libc numbers, but the ones that are passed to _write() */
#define STDERR 2

/* these values can be in LAST_INTERNAL_ERROR after a restart */
#define INTERNAL_ERROR_PSTACK_UFLOW -1
#define INTERNAL_ERROR_PSTACK_OFLOW -2
#define INTERNAL_ERROR_RSTACK_UFLOW -3
#define INTERNAL_ERROR_RSTACK_OFLOW -4
#define INTERNAL_ERROR_RTSTACK_UFLOW -5
#define INTERNAL_ERROR_RTSTACK_OFLOW -6
#define INTERNAL_ERROR_INVALID_OPCODE -7
#define INTERNAL_ERROR_MEM_FAULT -8
#define INTERNAL_ERROR_UNKNOWN_FF -9
#define INTERNAL_ERROR_TOKEN_READ -10
#define INTERNAL_ERROR_GENERAL -11
#define INTERNAL_ERROR_UNKNOWN_SPECIAL -12

static FILE * Ostream; /* used by reporting functions, so they can temporarily
											  print to different file descriptor */

/* main memory to work with */
static cell memory[VM_MEM];

typedef struct return_entry {
	inst * return_address;
	inst * current_call;
} return_entry;

/* check if current value of debug is greater or equal to val */
static bool debug_lvl(unsigned int val) {
	return (DEBUG_LEVEL >= val);
}

uint32_t lookup_ht_entry(uint8_t length, char* name) {
	uint32_t hash = 5381;
	for (int i = 0; i < length; i++) {
		hash = hash * 33 + name[i];
	}
	return (cell)dict+dict_hash_index[hash%256];
}

/* check if name in dictionary entry is a null-terminated string */
static unsigned char dict_entry_real_length( dict_entry * e)
{
	if (e->name[e->name_length - 1] == 0)
		return e->name_length - 1;
	else
		return e->name_length;
}

/* returns NULL if not found, otherwise points to dictionary entry */
static dict_entry * find_by_name(char *fname, unsigned char length)
{
	/* if (debug_lvl(1)) printf("looking for '%s'(%d) ", fname,length); */
	for(char * ptr=(char*)dict;
		 (ptr < ((char*)dict+sizeof(dict)))&&(((dict_entry*)ptr)->name_length > 0);
		 ptr += (((dict_entry*)ptr)->name_length + 4*sizeof(unsigned char) + sizeof(void*))) {
		dict_entry *dptr = (dict_entry*)ptr;
		unsigned char rl = dict_entry_real_length(dptr);
		/* if (debug_lvl(1)) printf("comparing to (%#lx): %s(%d); ",(uintptr_t)dptr->name,dptr->name,rl); */
		if (length != rl) continue;
		if (strncmp(fname,dptr->name,length)==0) {
			if (debug_lvl(1)) printf("found at: %#lx\n",(cell)dptr->address);
			return dptr;
		}
	}
	/* if (debug_lvl(1)) printf("not found\n"); */
	return (dict_entry *) NULL;
}

/* get the name of the word, only for debugging */
/* probably fails for non-null-terminated strings */
static char* find_by_address( inst * word)
{
	static char notfound[] = "(internal or private)";
	for (char * ptr=(char*)dict;
		  (ptr < ((char*)dict+sizeof(dict)))&&(((dict_entry*)ptr)->name_length > 0);
		  ptr += (((dict_entry*)ptr)->name_length + 3*sizeof(unsigned char) + sizeof(void*))) {
		dict_entry *dptr = (dict_entry*)ptr;
		if (dptr->address == word)
			return dptr->name;
	}
	return notfound;
}

static bool parse_number(char *str, cell * number){
	int num;
	/* if (debug_lvl(1)) printf("trying to read '%s' as number...",str); */
	unsigned int read = sscanf(str,"%i",&num);
	if (read == 1) {
		/* if (debug_lvl(1)) printf("got %d\n",num); */
		*number=(cell)num;
		return true;
	} else {
		/* if (debug_lvl(1)) printf("failed\n"); */
		return false;
	}
}

static void printstack(cell * sp, cell * stack)
{
	fprintf(Ostream, "stack:");
	for(cell* ptr = stack;ptr < sp;ptr++)
		{
			fprintf(Ostream, " %#lx",*ptr);
		}
	fprintf(Ostream, "\n");
}
static void print_return_stack(return_entry * sp, return_entry * stack, inst * base)
{
	fprintf(Ostream, "stack:");
	for(return_entry* ptr = sp-1;ptr >= stack;ptr--)
		{
			fprintf(Ostream, " {%#lx->%#lx}",((uintptr_t)ptr->current_call-(uintptr_t)base),
					 ((uintptr_t)ptr->return_address)-(uintptr_t) base);
		}
	fprintf(Ostream, "\n");
}


enum nesting_type {
	nesting_quot,
	nesting_list
};

static void backtrace(return_entry * sp, return_entry * stack, inst * base, inst * pc)
{
	fprintf(Ostream, "backtrace @ %#lx:\n",(uintptr_t)(pc-base));
	for(return_entry* ptr = sp-1;ptr >= stack;ptr--)
		{
			char *current_name = find_by_address(ptr->current_call);
			/* char *current_return = find_by_address(ptr->return_address); */
			fprintf(Ostream, "%#lx %s\n",(uintptr_t)(ptr->current_call - base),current_name);
		}
}


static void print_error(char * str)
{
	fprintf(stderr, "error: ");
	fprintf(stderr, str);
	fprintf(stderr, "\n");
}

	#define BACKTRACE() do {															\
	FILE * old_out = Ostream;															\
	Ostream = stderr;																		\
	printstack(psp,pstack);																\
	printstack(retainsp,retainstack);												\
	backtrace(returnsp,returnstack,(inst *)BASE,pc);							\
	Ostream = old_out;																	\
 }	while (0)																				\


	#define restart() do {if (RESTART == 0)										\
								 {printf("No restart defined with >>restart, resetting\n"); \
								  reset_system();} else {								\
																 pc = (inst*)RESTART; goto restart;}} while(0)

	#define handle_error(code) do {return code;} while(0)


	#define assert_pop(sp,min,name,fail_reason) if (sp <= min) { print_error(name "stack underflow");BACKTRACE();handle_error(fail_reason);}
	#define assert_push(sp,min,size,fail_reason) if (sp > min+size){ print_error("stack overflow");BACKTRACE();handle_error(fail_reason);}


/* empty ascending stack */
	#define push_(sp,val) *sp=val;sp++;
	#define pop_(sp) --sp;*sp;
	#define ppush(val) ({assert_push(psp,pstack,VM_PSTACK,INTERNAL_ERROR_PSTACK_OFLOW);push_(psp,val)})
	#define ppop() ({assert_pop(psp,pstack,"p",INTERNAL_ERROR_PSTACK_UFLOW);pop_(psp)})
	#define returnpush(val) ({assert_push(returnsp,returnstack,VM_RETURNSTACK,INTERNAL_ERROR_RSTACK_OFLOW);push_(returnsp,val)})
	#define returnpop() ({assert_pop(returnsp,returnstack,"return",INTERNAL_ERROR_RSTACK_UFLOW);pop_(returnsp)})
	#define retainpush(val) ({assert_push(retainsp,retainstack,VM_RETAINSTACK,INTERNAL_ERROR_RTSTACK_OFLOW);push_(retainsp,val)})
	#define retainpop() ({assert_pop(retainsp,retainstack,"retain",INTERNAL_ERROR_RTSTACK_OFLOW);pop_(retainsp)})

	#define peek_n(sp,nth) (*(sp-nth))

/* writes are only allowed into dedicated memory area for now */
	#define assert_memwrite(x) if ((x < memory) || (x >= (memory+VM_MEM))) {printf("prevented memory access at %#lx\n",x); BACKTRACE();handle_error(INTERNAL_ERROR_MEM_FAULT);}
/* reads are only allowed inside data space */
	#if __linux
		#define DATA_START __data_start
		#define DATA_END end
	#elif (PROCESSOR_EXPERT)
		#define DATA_START _sdata
		#define DATA_END end
	#elif (ATOLLIC_TRUESTUDIO)
		#define DATA_START _sdata
		#define DATA_END _edata
	#elif (CORTEX_M)
		#define DATA_START __data_start__
		#define DATA_END end
	#else
		#error "no data segment information"
	#endif

extern cell DATA_START;
extern cell DATA_END;

static void init_specials() {
	HANDLER = 0;
	MP = (cell)memory; /* start of user memory */
	BASE = (cell)&image; /* start of bytecode segment */
	OUTPUT_STREAM = 1;	/* output to standard output per default */
}

static FILE * current_fd(void)
{
	if (OUTPUT_STREAM == 2)
		return stderr;
	else
		return stdout;
}

int interpreter(short_jump_target start_base_address) {
	/* parameter stack */
	static cell pstack[VM_PSTACK]={0};
	static cell* psp;
	/* return stack */
	static return_entry returnstack[VM_RETURNSTACK]={{0}};
	static return_entry* returnsp;
	/* retain stack */
	static cell retainstack[VM_RETAINSTACK]={0};
	static cell* retainsp;
	static bool tailcall;
	inst *pc;

	/* initialize state */
	Ostream = stdout;
	pc = &image[(start_base_address ? : START_WORD_OFFSET)];
	init_specials();
	psp = &pstack[0];
	returnsp = &returnstack[0];
	retainsp = &retainstack[0];
	tailcall = true;

	cell x;								/* temporary value for operations */
	return_entry start_entry = {.return_address=NULL,.current_call = pc};
	/* single step debugging*/
	unsigned int debug_nest = 0; /* used in debug mode to track when
											* to stop single stepping*/
	bool debug_mode = false;
	#if DEBUG
	debug_mode=true;
	#endif
	returnpush(start_entry);
	while(1) {
		inst i;
	next:
		__attribute__((unused))
			/* if (debug_lvl(2)) { */
			/* 	printf("\n"); */
			/* 	printstack(psp,pstack); */
			/* 	printstack(retainsp,retainstack); */
			/* } */
		i= (*pc++);
	dispatch:
		if (debug_mode) {
			printf("\n");
			printstack(psp,pstack);
			printf("retain");
			printstack(retainsp,retainstack);
			printf("i:%#x\n",i); fflush(stdout);
			char * name = find_by_address((inst*)((cell)i<<(8*(sizeof(inst *)-sizeof(inst)))));
			if (name) {
				printf("%s\n",name);
				fflush(stdout);
			}
			(void)getc(stdin);
		}
		switch (i) {
	#define UNOP(op) { x=(op ((intptr_t) ppop())); ppush(x);} break
	#define BINOP(op) { x = ppop(); cell y = ppop(); ppush(((intptr_t)y) op ((intptr_t)x));} break
		case drop: ppop(); break;
		case zero: ppush(0); break;
		case one: ppush(1); break;
		case two: ppush(2); break;
		case add: BINOP(+);
		case mul: BINOP(*);
		case sub: BINOP(-);
		case neg: UNOP(-);
		case asl: BINOP(<<);
		case asr: BINOP(>>);
		case div: BINOP(/);
		case mod: BINOP(%);
		case bitand: BINOP(&);
		case bitor: BINOP(|);
		case bitxor: BINOP(^);
		case bitnot: UNOP(~);
		case gt: BINOP(>);
		case lt: BINOP(<);
		case _dup:
			ppush(peek_n(psp,1)); break;
		case memstart:
			ppush((cell)memory);
			break;
		case memend:
			ppush((cell)(memory+VM_MEM));
			break;
		case dictstart:
			ppush((cell)dict);
			break;
		case dictend:
			ppush((cell)(dict+VM_DICT));
			break;
		case cellsize:
			ppush((cell)sizeof(cell));
			break;
		case instbase:
			ppush((cell)INSTBASE);
			break;
		case ref:					  /* only gc knows a difference */
		case liti:                    /* literal wide integer */
			x=*((cell *)pc);
			ppush(x);
			pc+=sizeof(cell);
			break;
		case litc:              /* complex inline literal */
			{
				/* pc is already at the next item -> header byte */
				seq_header h = (seq_header)(*pc);
				ppush((cell)pc+1);    /* leave address of count byte on stack */
				pc += 2 + fe_seq_size(h,pc+1);
			} break;
		case strstart: {           /* ( -- countedstr ) */
			unsigned char len = *pc;
			ppush((cell)pc);
			pc += len+1;
		} break;
		case oplit:             /* literal primitive operation */
			x=(cell)*(pc++);
			ppush(x<<(8*(sizeof(cell)-sizeof(inst))));
			break;
		case litb:              /* byte literal */
			x=(cell)(*(pc++));
			ppush(x);
			break;
                case dref:
                        x=(cell)(*((short_jump_target*) pc));
                        ppush((cell)memory+x);
                        pc += sizeof(short_jump_target);
                        break;
		case bref:              /* reference to short-length in-memory data (type can be seen on-site)*/
		case blitq:             /* reference to in-memory quotation */
			x=(cell)(*((short_jump_target*) pc));
			ppush((cell) (BASE + ((short_jump_target) x)));
			pc += sizeof(short_jump_target);
			break;
		case _pwrite:
			fprintf(current_fd(), "%ld", ppop());
			break;
		case pwritex:
			fprintf(current_fd(), "%#lx", ppop());
			break;
		case writex:
			fprintf(current_fd(), "%lx", ppop());
			break;
		case emit:
			fputc(ppop(),current_fd());
			fflush(stdout);			/* TODO remove eventually */
			break;
		case receive:
			ppush(read_char()); break;
		case quit:
			printf("bye!\n");
			return 0;
		case qend: {
			return_entry e = returnpop();
			/* if (debug_lvl(2)) { */
			/* 	char * name = find_by_address(e.current_call); */
			/* 	if (name) { */
			/* 		printf("<- %s\n",name); */
			/* 		fflush(stdout); */
			/* 	} */
			/* } */
			if (debug_mode) {
				if (debug_nest > 0) {
					printf("<- %d\n",debug_nest);
					debug_nest--; }
				else {
					debug_mode=false; }
			}
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
			/* ( number of stack -- sp ) */
		case get_sp:
			switch (ppop()) {
			case 0 : ppush((cell)psp); break;
			case 1 : ppush((cell)retainsp); break;
			case 2 : ppush((cell)returnsp); break;
			default: ppush((cell)0); break;
			}
			break;
			/* ( val n -- ) */
		case set_sp:
			{
				unsigned char n = (unsigned char)ppop();
				cell* newsp = (cell*)ppop();
				switch (n) {
				case 0 : psp = newsp; break;
				case 1 : retainsp = newsp; break;
				case 2 : returnsp = (return_entry *)newsp; break;
				} break;
			}
			/* ( n -- val ) */
		case get_special:
			{
				unsigned char i = (unsigned char)ppop();
				if (i < NumSpecials)
					ppush(special_vars[i]);
				else {
					printf("illegal specials index: %d\n", i);
					handle_error(INTERNAL_ERROR_UNKNOWN_SPECIAL);
				}
			} break;
			/* ( val n -- ) */
		case set_special:
			{
				unsigned char i = (unsigned char)ppop();
				if (i < NumSpecials)
					special_vars[i] = ppop();
				else {
					printf("illegal specials index: %d\n", i);
					handle_error(INTERNAL_ERROR_UNKNOWN_SPECIAL);
				}
			} break;
			/* ( cond true false -- true/false ) */
		case truefalse:			  /* this one assumes the most about the stack right now */
			{
				cell false_cons = ppop();
				cell true_cons = ppop();
				cell cond = ppop();
				ppush(cond ? true_cons : false_cons);
			} break;
			/* ( -- countedstring ) */
		case token: {
			char *tok = read_token();
			/* if (debug_lvl(1)) printf("got token:%s\n",tok+1); */
			if (tok) {
            ppush((cell)tok);
			} else {
            print_error("token reader error");
            handle_error(INTERNAL_ERROR_TOKEN_READ);
			}} break;
			/* (countedstr -- countedstr/dict_entry foundp) */
		case search: {
			cell name_to_find=ppop();
			dict_entry * addr=find_by_name(((char*)name_to_find)+1,*((char *) name_to_find)); /* skip countbyte */
			ppush(addr==NULL ? name_to_find : (cell)addr);
			ppush(addr==NULL ? false : true);
		}
			break;
		case lookup_name: {
			cell length = ppop();
			cell name = ppop();
			ppush(lookup_ht_entry((uint8_t) length,(char *) name)); }
			break;
		case scall:
		_scall:
			/* check if call target is primitive, if yes, substitute execution (tail call), since call only
				applies to quotations */
			x = ppop();
			if (x >= INSTBASE_CELL) {
            /* if (debug_lvl(2)) printf("s(t)call: prim\n"); */
            i=(x>>(8*(sizeof(inst*)-sizeof(inst))));
            goto dispatch;
			} else {
            /* if (debug_lvl(2)) printf("scall: inmem word\n"); */
            goto nested_call;
			} break;
		case stcall:            /* WARNING: copied code above */
			if (!tailcall) goto _scall;
			x = ppop();
			if (x >= INSTBASE_CELL) {
            /* if (debug_lvl(2)) printf("stcall: prim\n"); */
            i=(x>>(8*(sizeof(inst*)-sizeof(inst))));
            goto dispatch;      /* already a tail call */
			} else {
            /* if (debug_lvl(2)) printf("stcall: inmem word\n"); */
            goto tail_call;
			} break;
		case stack_show:
			printf("\np");
			printstack(psp,pstack);
			printf("retain");
			printstack(retainsp,retainstack);
			printf("return");
			print_return_stack(returnsp,returnstack,(inst *)BASE);
			break;
		case stack_level: /* ( -- u ) */
			ppush(psp-pstack); break;
		case parsenum: {
			char *str = (char *)ppop();
			cell num = 0xa5a5a5a5;
			bool success=parse_number(str+1,&num);
			ppush(success ? num : (cell) str);
			ppush((cell)success);
		} break;
		case nop:
			break;
			/* ( -- data-start data-end mem-start mem-end ) */
		case memrange:
			ppush((cell) &DATA_START);
			ppush((cell) &DATA_END);
			ppush((cell) memory);
			ppush((cell) memory+VM_MEM*sizeof(cell));
			break;
			/* ( value address -- ) */
		case setmem:
			x=ppop();
			*((cell*)x)=(ppop());
			break;
		case setmem8:
			x=ppop();
			*((char*)x)=((ppop()&0xff));
			break;
			/*  (address -- value )) */
		case getmem: {
			cell *addr=(cell *)ppop();
			x = *addr;
			ppush(x);
		} break;
		case getmem8: {
			char *addr=(char *)ppop();
			x = (cell)(*(addr));
			ppush(x);
		} break;
		case aend:
			handle_error(INTERNAL_ERROR_INVALID_OPCODE);
			break;
			/* skip over to end of quotation , leave starting address on parameter stack*/
		case qstart: {
			uint8_t l = *((uint8_t *)pc) + 1;
			/* if (debug_lvl(2)) printf("qstart saving %#lx\n",(uintptr_t)pc-(uintptr_t)base); */
			/* if (debug_lvl(2)) printf("pc skipping %d bytes\n",l); */
			ppush((cell)(pc + 1));
			/* skip over quotation length, leaving pc after qend */
			pc = pc + l + 1;
		} break;
		case bcall: {
			_bcall:
			x= (cell)(BASE+*((short_jump_target *)pc));
			pc += sizeof(short_jump_target);
			goto nested_call;
		} break;
			/* base-relative tail-call, effectively a goto */
		case btcall:
			if (!tailcall) goto _bcall;
			x=(cell)(BASE+*((short_jump_target *)pc));
			goto tail_call;
			break;
		case acall: {
			x =(cell) *((jump_target *)pc);
			pc += sizeof(jump_target);
			goto nested_call;
		} break;
		case clear:
			psp = &pstack[0];
			break;
		case error:
			printf("error!\n");
			printf("\np");
			printstack(psp,pstack);
			printf("retain");
			printstack(retainsp,retainstack);
			printf("return");
			print_return_stack(returnsp,returnstack,(inst *)BASE);
			BACKTRACE();
			handle_error(INTERNAL_ERROR_GENERAL);
			break;
		case tstart:
			start_timer();
			break;
			/* end timer ( -- usecs secs ) */
		case tend:
			{
				unsigned int sec,usec;
				end_timer(&sec,&usec);
				ppush(usec);
				ppush(sec);
			} break;
		case tail:
			tailcall=true; break;
		case notail:
			tailcall=false; break;
		case reset:
			reset_system();
			break;
		case debug:
			if (!debug_mode) {
				debug_mode=true;
				/* tailcall = false; */
			}
			break;
			/* getting an address from the foreign-function lut ( i -- addr ) */
		case ff:
			{
	#ifndef FF_LENGTH
		#define FF_LENGTH 0
	#endif
				unsigned int i = ppop();
				if (i >= FF_LENGTH)
					{
						printf("no ff entry with index %i\n",i);
						BACKTRACE();
						handle_error(INTERNAL_ERROR_UNKNOWN_FF);
					}
				ppush((cell)FF_Table[i]);
			} break;
		case ccall_i:
			{
				int(*fun)(int) = (int (*)(int))ppop();
				int i1 = (int)ppop();
				int res = fun(i1);
				ppush((cell)res);
			} break;
		case ccall_s:
			{
				int(*fun)(short) = (int (*)(short))ppop();
				short s1 = (short)ppop();
				int res = fun(s1);
				ppush((cell)res);
			} break;
		case ccall_b:
			{
				int(*fun)(char) = (int (*)(char))ppop();
				int b1 = (char)ppop();
				int res = fun(b1);
				ppush((cell)res);
			} break;
		case ccall_bi:
			{
				int(*fun)(char, int) = (int (*)(char,int))ppop();
				int i2 = (int)ppop();
				char b1 = (char)ppop();
				int res = fun(b1,i2);
				ppush((cell)res);
			} break;
		case ccall_ib:
			{
				int(*fun)(int, char) = (int (*)(int, char))ppop();
				char b2 = (char)ppop();
				int i1 = (int)ppop();
				int res = fun(i1,b2);
				ppush((cell)res);
			} break;
		case ccall_is:
			{
				int(*fun)(int,short) = (int (*)(int,short))ppop();
				short s2 = (short)ppop();
				int i1 = (int)ppop();
				int res = fun(i1,s2);
				ppush((cell)res);
			} break;
		case ccall_iis:
			{
				int(*fun)(int,int,short) = (int (*)(int,int,short))ppop();
				short s3 = (short)ppop();
				int i2 = (int)ppop();
				int i1 = (int)ppop();
				int res = fun(i1,i2,s3);
				ppush((cell)res);
			} break;
		case ccall_iii:
			{
				int(*fun)(int,int,int) = (int (*)(int,int,int))ppop();
				int i3 = (int)ppop();
				int i2 = (int)ppop();
				int i1 = (int)ppop();
				int res = fun(i1,i2,i3);
				ppush((cell)res);
			} break;
		case ccall_ii:
			{
				int(*fun)(int,int) = (int (*)(int,int))ppop();
				int i2 = (int)ppop();
				int i1 = (int)ppop();
				int res = fun(i1,i2);
				ppush((cell)res);
			} break;
		case ccall_v:
			{
				int(*fun)(void) = (int (*)(void))ppop();
				int res = fun();
				ppush((cell)res);
			} break;
		case ccall_lit: break;
		default:
			printf("unimplemented instruction %#x\n",i);
			/* BACKTRACE(); */
			handle_error(INTERNAL_ERROR_INVALID_OPCODE);
		}
		goto end_inst;
	nested_call:
		{
			inst *next_word = (inst *) x;
			/* if (debug_lvl(2)) printf("w:%#lx\n",(cell)next_word-(uintptr_t)base); */
			/* char * name = find_by_address(next_word); */
			/* if (name) { */
         /*    if (debug_lvl(1)) printf("-> %s\n",name); */
         /*    fflush(stdout); */
			/* } */
			return_entry e = {.return_address = pc, .current_call=next_word};
			returnpush(e);
			if (debug_mode) {
            char * name = find_by_address(next_word);
            debug_nest++;
            printf("calling: %s -> %d\n",name,debug_nest);
			}
			pc=next_word;
		}
		goto end_inst;
	tail_call:
		{
			inst *next_word = (inst *) x;
			/* if (debug_lvl(2)) printf("w:%#lx\n",(cell)next_word-(uintptr_t)base); */
			/* char * name = find_by_address(next_word); */
			/* if (name) { */
         /*    if (debug_lvl(2)) printf("..-> %s\n",name); */
         /*    fflush(stdout); */
			/* } */
			if (debug_mode) {
            char * name = find_by_address(next_word);
            printf("tail calling: %s -> %d\n",name,debug_nest);
			}
			/* dont update caller field to ease debugging */
			/* returnsp->current_call = next_word; */
			pc = next_word;
		}
		goto end_inst;
	end_inst:
		(void)0;
	}
}

#endif
