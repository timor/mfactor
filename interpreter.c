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

/* target specific stuff */
#include "runtime.h"
#include "reset_system.h"

/* entry in name dictionary */
/* TODO: ensure correct scanning direction so that skipping over entries stays trivial */
typedef struct dict_entry
{
	void * address;					/* pointer into memory */
	unsigned char immediatep;		/* may include other flags later (inline, recursive, etc) */
	unsigned char name_length;
	char name[];
}	__attribute__((packed)) dict_entry;
/* TODO: doc quirk that primitive names are null-terminated */

typedef struct return_entry {
	inst * return_address;
	inst * current_call;
} return_entry;

/* dictionary grows up*/
#include "generated/stdlib.dict.h"

/* returns NULL if not found*/
static inst* find_by_name(char *fname)
{
  IFTRACE1(printf("looking for '%s' ", fname));
  for(char * ptr=(char*)dict;
		(ptr < ((char*)dict+sizeof(dict)))&&(((dict_entry*)ptr)->name_length > 0);
		ptr += (((dict_entry*)ptr)->name_length + 2*sizeof(unsigned char) + sizeof(void*))) {
	 dict_entry *dptr = (dict_entry*)ptr;
	 IFTRACE1(printf("comparing to (%#lx): %s; ",(uintptr_t)dptr->name,dptr->name));
	 if (strncmp(fname,dptr->name,dptr->name_length)==0) {
		IFTRACE1(printf("found at: %#lx\n",(cell)dptr->address));
		return dptr->address;
	 }
  }
  IFTRACE1(printf("not found\n"));
  return (inst *) NULL;
}

/* get the name of the word, only for debugging */
/* probably fails for non-null-terminated strings */
static char* find_by_address( inst * word)
{
  static char notfound[] = "(internal or private)";
  for (char * ptr=(char*)dict;
       (ptr < ((char*)dict+sizeof(dict)))&&(((dict_entry*)ptr)->name_length > 0);
       ptr += (((dict_entry*)ptr)->name_length + 2*sizeof(unsigned char) + sizeof(void*))) {
    dict_entry *dptr = (dict_entry*)ptr;
    if (dptr->address == word)
      return dptr->name;
  }
  return notfound;
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
	for(cell* ptr = stack;ptr < sp;ptr++)
		{
          printf(" %#lx",*ptr);
		}
	printf("\n");
}
static void print_return_stack(return_entry * sp, return_entry * stack, inst * base)
{
	printf("stack:");
	for(return_entry* ptr = sp-1;ptr >= stack;ptr--)
		{
          printf(" {%#lx->%#lx}",((uintptr_t)ptr->current_call-(uintptr_t)base),
                 ((uintptr_t)ptr->return_address)-(uintptr_t) base);
		}
	printf("\n");
}


enum nesting_type {
	nesting_quot,
	nesting_list
};

/* skip over instruction stream until a certain one, supports nesting */
static inst * skip_to_instruction(inst* pc,inst until, inst nest_on, inst *base){
	inst *ptr=pc;
    for(inst i= *ptr; (i != until); i=*(++ptr)) {
		  IFTRACE2(printf("skipping over %#x, ",i));
          if (i == nest_on)
            ptr=skip_to_instruction(ptr+1, until, nest_on, base);
            else
              switch (i) {
              case lit:
                ptr+=sizeof(cell);
                break;
              case litb:
              case oplit:
                ptr+=sizeof(inst);
                break;
              case acall:
                ptr+=sizeof(jump_target);
                break;
              case blitq:
              case bcall:
              case btcall:
                ptr+=sizeof(short_jump_target);
                break;
              }
    }
    IFTRACE2(printf("skipped until %#lx\n",(uintptr_t)ptr-(uintptr_t)base));
	return ptr;
}

static void backtrace(return_entry * sp, return_entry * stack, inst * base, inst * pc) 
{
  printf("backtrace @ %#lx:\n",(uintptr_t)(pc-base));
	for(return_entry* ptr = sp-1;ptr >= stack;ptr--)
		{
          char *current_name = find_by_address(ptr->current_call);
          /* char *current_return = find_by_address(ptr->return_address); */
          printf("%#lx %s\n",(uintptr_t)(ptr->current_call - base),current_name);
		}
}


static void print_error(char * str)
{
  printf("error: ");
  printf(str);
  printf("\n");
}

#define BACKTRACE() (printstack(psp,pstack),printstack(retainsp,retainstack),backtrace(returnsp,returnstack,base,pc));

#define assert_pop(sp,min) if (sp <= min) { print_error("stack underflow");BACKTRACE();return;}
#define assert_push(sp,min,size) if (sp > min+size){ print_error("stack overflow");BACKTRACE();return;}


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

#include "generated/stdlib.code.h"

static cell memory[VM_MEM];
/* writes are only allowed into dedicated memory area for now */
#define assert_memwrite(x) if ((x < memory) || (x >= (memory+VM_MEM))) {printf("prevented memory access at %#lx\n",x); BACKTRACE();return;}
/* reads are only allowed inside data space */
#if __linux
#define DATA_START __data_start
#define DATA_END end
#elif (PROCESSOR_EXPERT)
#define DATA_START _sdata
#define DATA_END end
#elif (CORTEX_M)
#define DATA_START __data_start__
#define DATA_END end
#else
#error "no data segment information"
#endif

extern cell DATA_START;
extern cell DATA_END;

#define assert_memread(x) if ((x < &DATA_START)||(x >= &DATA_END)) {printf("prevented memory read at %#lx\n",x); BACKTRACE(); return;}


void interpreter(inst * user_program)
{
	static bool tailcall = true;
	/* parameter stack */
	static cell pstack[VM_PSTACK]={0};
	cell* psp = &pstack[0];
	/* return stack, not preserved across calls */
	return_entry returnstack[VM_RETURNSTACK]={{0}};
	return_entry* returnsp = &returnstack[0];
	/* retain stack */
	static cell retainstack[VM_RETAINSTACK]={0};
	cell* retainsp =&retainstack[0];
	/* catch stack */
	/* static cell cstack[VM_CSTACK]={0}; */
	/* static cell* csp = &cstack[0]; */
	/* TODO: name stack */
	cell x;								/* temporary value for operations */
    static inst *base=stdlib;  /* base address for base-relative short calls */
	inst *pc = user_program ? : &stdlib[0];
	return_entry start_entry = {.return_address=NULL,.current_call = pc};
	returnpush(start_entry);
    while(1) {
		inst i;
	next:
		__attribute__((unused))
        IFTRACE1(printf("\n"));
		IFTRACE1(printstack(psp,pstack));
		IFTRACE2(printstack(retainsp,retainstack));
		/* IFTRACE2(print_return_stack(returnsp,returnstack)); */
		i= (*pc++);

    dispatch:
	#if (TRACE_LEVEL >= 1)
        IFTRACE2(printf("i:%#x\n",i));
        {
          char * name = find_by_address((inst*)((cell)i<<(8*(sizeof(inst *)-sizeof(inst)))));
          if (name) {
            IFTRACE1(printf("%s\n",name));
            fflush(stdout);
          }
        }
	#endif
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
        case lit:
          x=*((cell *)pc);
          ppush(x);
          pc+=sizeof(cell);
          break;
        case oplit:
          x=(cell)*(pc++);
          ppush(x<<(8*(sizeof(cell)-sizeof(inst))));         /*  */
          break;
        case litb:
          x=(cell)(*(pc++));
          ppush(x);
          break;
        case blitq:
          x=(cell)(*((short_jump_target*) pc));
          ppush((cell) (base + ((short_jump_target) x)));
          pc += sizeof(short_jump_target);
          break;
        case _pwrite:
          printf("%ld",ppop());
          break;
        case pwritex:
          printf("%#lx",ppop());
          break;
        case emit:
          putchar(ppop());
          fflush(stdout);			/* TODO remove eventually */
          break;
        case receive:
          ppush(read_char()); break;
        case quit:
          printf("bye!\n");
          return;
        case qend: {
          return_entry e = returnpop();
          char * name = find_by_address(e.current_call);
          if (name) {
            IFTRACE1(printf("<- %s\n",name));
            fflush(stdout);
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
          IFTRACE1(printf("got token:%s\n",tok+1));
          if (tok) {
            ppush((cell)tok);
          } else {
            print_error("token reader error");
            return;
          }} break;
          /* (countedstr -- quot/addr foundp) */
        case find: {
          cell name_to_find=ppop();
          inst * addr=find_by_name(((char*)name_to_find)+1); /* skip countbyte */
          ppush(addr==NULL ? name_to_find : (cell)addr);
          ppush(addr==NULL ? false : true);
        }
          break;
        case scall:
	 _scall:
          /* check if call is primitive, if yes, substitute execution (tail call), since call only
             applies to quotations */
          x = ppop();
          if (x >= INSTBASE_CELL) {
            IFTRACE2(printf("s(t)call: prim\n"));
            i=(x>>(8*(sizeof(inst*)-sizeof(inst))));
            goto dispatch;
          } else {
            assert_memread((cell *)x);
            IFTRACE2(printf("scall: inmem word\n"));
            goto nested_call;
          } break;
        case stcall:            /* WARNING: copied code above */
			  if (!tailcall) goto _scall;
          x = ppop();
          if (x >= INSTBASE_CELL) {
            IFTRACE2(printf("stcall: prim\n"));
            i=(x>>(8*(sizeof(inst*)-sizeof(inst))));
            goto dispatch;      /* already a tail call */
          } else {
            assert_memread((cell *)x);
            IFTRACE2(printf("stcall: inmem word\n"));
            goto tail_call;
          } break;
        case stack_show:
          printf("\np");
          printstack(psp,pstack);
          printf("retain");
          printstack(retainsp,retainstack);
          printf("return");
          print_return_stack(returnsp,returnstack,base);
          break;
        case parsenum: {
          char *str = (char *)ppop();
          assert_memread((cell *)str);
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
          ppush((cell) memory+VM_MEM);
          break;
          /* ( value address -- ) */
        case _set:
          x=ppop();
          /* assert_memwrite((cell *)x); */
          *((cell*)x)=(ppop());
          break;
        case _setbyte:
          x=ppop();
          /* assert_memwrite((cell*)x); */
          *((char*)x)=((ppop()&0xff));
          break;
          /*  (address -- value )) */
        case _get: {
          cell *addr=(cell *)ppop();
          /* assert_memread(addr); */
          x = *addr;
          ppush(x);
        } break;
        case _getbyte: {
          char *addr=(char *)ppop();
          /* assert_memread((cell *)addr); */
          x = (cell)(*(addr));
          ppush(x);
        } break;
          /* ( -- countedstr ) */
        case strstart: {
          unsigned char len = *pc;
          ppush((cell)pc);
          pc += len+1;
        } break;
          /* skip over to end of quotation , leave starting address on parameter stack*/
        case qstart:
          IFTRACE1(printf("qstart saving %#lx\n",(uintptr_t)pc-(uintptr_t)base));
          ppush((cell)pc);
          pc=skip_to_instruction(pc,qend,qstart,base);
          pc+=1;
          break;
        case bcall: {
			 _bcall:
          x= (cell)(base+*((short_jump_target *)pc));
          pc += sizeof(short_jump_target);
          goto nested_call;
        } break;
          /* base-relative tail-call, effectively a goto */
        case btcall:
			  if (!tailcall) goto _bcall;
          x=(cell)(base+*((short_jump_target *)pc));
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
        case psplevel:
          x=(cell)(psp-pstack);
          ppush(x);
          break;
        case error:
          printf("error!\n");
          printf("\np");
          printstack(psp,pstack);
          printf("retain");
          printstack(retainsp,retainstack);
          printf("return");
          print_return_stack(returnsp,returnstack,base);
          BACKTRACE();
          return;
          break;
        case tstart:
          start_timer();
          break;
          /* end timer ( -- usecs secs ) */
        case tend: 
        { 
          long int sec,usec;
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
        default:
          printf("unimplemented instruction %#x\n",i);
          BACKTRACE();
          return;
        }
        goto end_inst;
    nested_call:
        {
          inst *next_word = (inst *) x;
          IFTRACE2(printf("w:%#lx\n",(cell)next_word-(uintptr_t)base));
          char * name = find_by_address(next_word);
          if (name) {
            IFTRACE1(printf("-> %s\n",name));
            fflush(stdout);
          }
          return_entry e = {.return_address = pc, .current_call=next_word};
          returnpush(e);
          pc=next_word;
        }
        goto end_inst;
    tail_call:
        {
          inst *next_word = (inst *) x;
          IFTRACE2(printf("w:%#lx\n",(cell)next_word-(uintptr_t)base));
          char * name = find_by_address(next_word);
          if (name) {
            IFTRACE1(printf("..-> %s\n",name));
            fflush(stdout);
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
