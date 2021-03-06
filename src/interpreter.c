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

/* main memory to work with */
static cell memory[VM_MEM];
#define _NumSpecials 10
static const unsigned char NumSpecials = _NumSpecials;
static cell special_vars[_NumSpecials];
/* currently implemented special variables
0: MP - memory write pointer
1: HANDLER - handler frame location in r(etain) stack (dynamic chain for catch frames)
2: DEBUG_LEVEL - 0 to turn off, increasing will produce more verbose debug output
3: RESTART - word where to restart when hard error occured
4: STEP_HANDLER - address of handler which can be used for single stepping
5: BASE - address of current 64k segment base
6: OUTPUT_STREAM: 1: stdout, 2: stderr, 3: null
*/
#define MP special_vars[0]
#define HANDLER special_vars[1]
#define DEBUG_LEVEL special_vars[2]
#define BASE special_vars[5]
#define OUTPUT_STREAM special_vars[6]
/* known stream descriptors for OUTPUT_STREAM */
#define STDOUT 1
#define STDERR 2
#define NULLOUT 3
static void init_specials() {
   HANDLER = 0;
   MP = (cell)memory; /* start of user memory */
   BASE = (cell)&image; /* start of bytecode segment */
   OUTPUT_STREAM = STDOUT; /* output to standard output per default */
}
static FILE * Ostream; /* used by reporting functions, so they can temporarily
                          print to different file descriptor */


/* get the current stdio FILE from the special variable, or NULL if unknown or muted by
 * choosing NULLOUT */
static FILE * current_fd(void)
{
        if (OUTPUT_STREAM == 2)
                return stderr;
        else if (OUTPUT_STREAM == 1)
                return stdout;
        else
                return NULL;
}
typedef struct return_entry {
   inst * return_address;
   inst * current_call;
} return_entry;
uint32_t lookup_ht_entry(uint8_t length, char* name) {
   uint32_t hash = 5381;
   for (int i = 0; i < length; i++) {
      hash = hash * 33 + name[i];
   }
   return (cell)dict+dict_hash_index[hash%256];
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
   unsigned int read = sscanf(str,"%i",&num);
   if (read == 1) {
      *number = (cell)num;
      return true;
   } else {
      return false;
   }
}
/* display data stack entries */
static void printstack(cell * sp, cell * stack)
{
   fprintf(Ostream, "stack:");
   for(cell* ptr = stack;ptr < sp;ptr++)
   {
      fprintf(Ostream, " %#lx",*ptr);
   }
   fprintf(Ostream, "\n");
}

/* display return stack entries */
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

/* print a backtrace of the return stack */
static void backtrace(return_entry * sp, return_entry * stack, inst * base, inst * pc)
{
   fprintf(Ostream, "backtrace @ %#lx:\n",(uintptr_t)(pc-base));
   for(return_entry* ptr = sp-1;ptr >= stack;ptr--)
   {
      char *current_name = find_by_address(ptr->current_call);
      fprintf(Ostream, "%#lx %s\n",(uintptr_t)(ptr->current_call - base),current_name);
   }
}
static void print_error(char * str)
{
   fprintf(stderr, "error: ");
   fprintf(stderr, str);
   fprintf(stderr, "\n");
}
#define BACKTRACE() do {                                 \
      FILE * old_out = Ostream;                          \
      Ostream = stderr;                                  \
      printstack(psp,pstack);                            \
      printstack(retainsp,retainstack);                  \
      backtrace(returnsp,returnstack,(inst *)BASE,pc);   \
      Ostream = old_out;                                 \
   }       while (0)
#define handle_error(code) do {return code;} while(0)
#define assert_pop(sp,min,name,fail_reason) if (sp <= min) { print_error(name "stack underflow");BACKTRACE();handle_error(fail_reason);}
#define assert_push(sp,min,size,fail_reason) if (sp > min+size){ print_error("stack overflow");BACKTRACE();handle_error(fail_reason);}
#define peek_n(sp,nth) (*(sp-nth))
/* push value onto stack indicated by stack pointer sp */
#define push_(sp,val) *sp=val;sp++;
/* pop value from stack indicated by stack pointer sp */
#define pop_(sp) --sp;*sp;
#define ppush(val) ({assert_push(psp,pstack,VM_PSTACK,INTERNAL_ERROR_PSTACK_OFLOW);push_(psp,val)})
#define ppop() ({assert_pop(psp,pstack,"p",INTERNAL_ERROR_PSTACK_UFLOW);pop_(psp)})
#define returnpush(val) ({assert_push(returnsp,returnstack,VM_RETURNSTACK,INTERNAL_ERROR_RSTACK_OFLOW);push_(returnsp,val)})
#define returnpop() ({assert_pop(returnsp,returnstack,"return",INTERNAL_ERROR_RSTACK_UFLOW);pop_(returnsp)})
#define retainpush(val) ({assert_push(retainsp,retainstack,VM_RETAINSTACK,INTERNAL_ERROR_RTSTACK_OFLOW);push_(retainsp,val)})
#define retainpop() ({assert_pop(retainsp,retainstack,"retain",INTERNAL_ERROR_RTSTACK_OFLOW);pop_(retainsp)})

int interpreter(short_jump_target start_address) {

   /* parameter stack */
   static cell pstack[VM_PSTACK]={0};
   static cell* psp;
   psp = &pstack[0];
   /* return stack */
   static return_entry returnstack[VM_RETURNSTACK]={{0}};
   static return_entry* returnsp;
   returnsp = &returnstack[0];
   /* retain stack */
   static cell retainstack[VM_RETAINSTACK]={0};
   static cell* retainsp;
   retainsp = &retainstack[0];
   inst *pc;
   pc = &image[(start_address ? : START_WORD_OFFSET)];  /* point to the start of the program */
   static bool tailcall;
   tailcall = true;  /* enable tail call jumping by default */
   cell x; /* temporary value for operations */
   /* single step debugging*/
   unsigned int debug_nest = 0; /* used in debug mode to track when
                                 * to stop single stepping*/
   bool debug_mode = false;
   #if DEBUG
   debug_mode=true;
   #endif

   Ostream = stdout;  /* print everything to stdout per default */
   init_specials();

   while(1) {
      inst i;
      i = (*pc++);
   dispatch:
      
      switch(i) {
         case drop: ppop(); break;
         case _dup: ppush(peek_n(psp,1)); break;
         case swap: {
            x=ppop();
            cell y = ppop();
            ppush(x);
            ppush(y);
         } break;
         case to_r: retainpush(ppop()); break;
         case r_from: ppush(retainpop()); break;
         case clear: psp = &pstack[0]; break;
         #define UNOP(op) {                              \
               x=(op ((intptr_t) ppop()));               \
               ppush(x);                                 \
            } break
         #define BINOP(op) {                                                     \
               x = ppop();                                                       \
               cell y = ppop();                                                  \
               ppush(((intptr_t)y) op ((intptr_t)x));                            \
            } break
         case add: BINOP(+); break;
         case mul: BINOP(*); break;
         case sub: BINOP(-); break;
         case neg: UNOP(-); break;
         case asl: BINOP(<<); break;  /* arithmetic shift left */
         case asr: BINOP(>>); break;  /* arithmetic shift right */
         case div: BINOP(/); break;
         case mod: BINOP(%); break;
         case bitand: BINOP(&); break;
         case bitor: BINOP(|); break;
         case bitxor: BINOP(^); break;
         case bitnot: UNOP(~); break;
         case gt: BINOP(>); break;
         case lt: BINOP(<); break;
         case eql: BINOP(==); break;
         case zero: ppush(0); break;
         case one: ppush(1); break;
         case two: ppush(2); break;
         case memstart: ppush((cell)memory); break;
         case memend: ppush((cell)(memory+VM_MEM)); break;
         case memrange:
            ppush((cell) memory);
            ppush((cell) memory+VM_MEM*sizeof(cell));
            break;
         case dictstart: ppush((cell)dict); break;
         case dictend: ppush((cell)(dict+VM_DICT)); break;
         case cellsize: ppush((cell)sizeof(cell)); break;
         case instbase: ppush((cell)INSTBASE); break;
         case get_sp:
            switch (ppop()) {
               case 0 : ppush((cell)psp); break;
               case 1 : ppush((cell)retainsp); break;
               case 2 : ppush((cell)returnsp); break;
               default: ppush((cell)0); break;
            } break;
         case set_sp:
            {
               unsigned char n = (unsigned char)ppop();
               cell* newsp = (cell*)ppop();
               switch (n) {
                  case 0 : psp = newsp; break;
                  case 1 : retainsp = newsp; break;
                  case 2 : returnsp = (return_entry *)newsp; break;
               }
            } break;
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
         case stack_level: ppush(psp-pstack); break;
         case litb:              /* byte literal */
           x=(cell)(*(pc++));
           ppush(x);
           break;
         case ref:
         case liti:               /* cell-wide literal */
           x=*((cell *)pc);
           ppush(x);
           pc+=sizeof(cell);
           break;
         case litc: {              /* complex inline literal */
           /* pc is already at the next item -> header byte */
           seq_header h = (seq_header)(*pc);
           ppush((cell)pc+1);    /* leave address of count byte on stack */
           pc += 2 + fe_seq_size(h,pc+1);
           } break;
         case oplit:             /* literal primitive operation */
            x=(cell)*(pc++);
            ppush(x<<(8*(sizeof(cell)-sizeof(inst))));
            break;
         case qstart: {
            uint8_t l = *((uint8_t *)pc) + 1;
            ppush((cell)(pc + 1));
            /* skip over quotation length and count byte, leaving pc after qend */
            pc = pc + l + 1;
         } break;
         case emit:
            if (current_fd() != NULL) {
               fputc(ppop(),current_fd());
               fflush(stdout);                 /* TODO remove when flushing is delegated to
                                                * higher level calls */
            } else
               (void) ppop();
            break;
         case receive:
            ppush(read_char()); break;
         case _pwrite:
            if (current_fd() != NULL)
               fprintf(current_fd(), "%ld", ppop());
            else
               (void) ppop();
            break;
         case pwritex:
            if (current_fd() != NULL)
               fprintf(current_fd(), "%#lx", ppop());
            else
               (void) ppop();
            break;
         case writex:
            if (current_fd() != NULL)
               fprintf(current_fd(), "%lx", ppop());
            else
               (void) ppop();
            break;
         case bcall: {  /* base-relative call */
         _bcall:
            x = (cell)(BASE + *((short_jump_target *)pc));  /* set the target */
            pc += sizeof(short_jump_target);
            goto nested_call;
         } break;
         case btcall:   /* base-relative tail-call, effectively a goto */
            if (!tailcall) goto _bcall;
            x = (cell)(BASE + *((short_jump_target *)pc));  /* set the target */
            goto tail_call;
            break;
         case acall: {  /* absolute call */
            x = (cell) *((jump_target *)pc);  /* set the target */
            pc += sizeof(jump_target);
            goto nested_call;
         } break;
         case scall:
         _scall:
            /* check if call target is primitive, if yes, substitute execution (tail call), since call only
               applies to quotations */
            x = ppop();  /* set the target */
            if (x >= INSTBASE_CELL) {
               i = (x >> (8 * (sizeof(inst *) - sizeof(inst))));
               goto dispatch;  /* calling a primitive "substitutes" the call with the primitive */
            } else {
               goto nested_call;
            } break;
         case stcall:
            if (!tailcall) goto _scall;
            x = ppop();  /* set the target */
            if (x >= INSTBASE_CELL) {
               i=( x >> (8 * (sizeof(inst*) - sizeof(inst))));
               goto dispatch;      /* already a tail call */
            } else {
               goto tail_call;
            } break;
         case qend: {
            return_entry e = returnpop();
            if (debug_mode) {
               if (debug_nest > 0) {
                  printf("<- %d\n",debug_nest);
                  debug_nest--; }
               else {
                  debug_mode=false; }
            }
            pc=e.return_address;
         } break;
         case truefalse:
            {
               cell false_cons = ppop();
               cell true_cons = ppop();
               cell cond = ppop();
               ppush(cond ? true_cons : false_cons);
            } break;
         case setmem:
                 x = ppop();
                 *((cell*)x) = (ppop());
                 break;
         case setmem8:
                 x=ppop();
                 *((char*)x) = ((ppop() & 0xff));
                 break;
         case getmem: {
                 cell *addr = (cell *)ppop();
                 x = *addr;
                 ppush(x);
         } break;
         case getmem8: {
                 char *addr = (char *)ppop();
                 x = (cell)(*(addr));
                 ppush(x);
         } break;
         case ff: {
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
         case ccall_lit: break;  /* address is literal, nothing happens */
         case nop: break;
         case dref:
            x=(cell)(*((short_jump_target*) pc));
            ppush((cell)memory+x);
            pc += sizeof(short_jump_target);
            break;
         case bref:              /* reference to short-length in-memory data (type can be seen on-site)*/
         case blitq:             /* deprecated */
            x=(cell)(*((short_jump_target*) pc));
            ppush((cell) (BASE + ((short_jump_target) x)));
            pc += sizeof(short_jump_target);
            break;
         case quit:  /* quit the interpreter, returning 0 */
            printf("quitting interpreter!\n");
            return 0;
         case token: {  /* get one token from standard input */
            char *tok = read_token();
            if (tok) {
               ppush((cell)tok);
            } else {
               print_error("token reader error");
               handle_error(INTERNAL_ERROR_TOKEN_READ);
            }} break;
         case lookup_name: {  /* provide a search start for the name (addr length) by using
                               * the hash table lookup */
            cell length = ppop();
            cell name = ppop();
            ppush(lookup_ht_entry((uint8_t) length,(char *) name)); }
            break;
         case error:  /* trigger internal error (bypasses any exception handling) */
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
         case tstart:  /* start the timer */
            start_timer();
            break;
         case tend:  /* end the timer, return measurement results ( -- usecs secs ) */
            {
               unsigned int sec,usec;
               end_timer(&sec,&usec);
               ppush(usec);
               ppush(sec);
            } break;
         case parsenum: {  /* parse the (c)string at the address on top of stack as number */
            char *str = (char *)ppop();
            cell num = 0xa5a5a5a5;
            bool success=parse_number(str+1,&num);
            ppush(success ? num : (cell) str);
            ppush((cell)success);
         } break;
         case tail:  /* activate tail call elimination */
            tailcall=true; break;
         case notail:  /* deactivate tail call elimination */
            tailcall=false; break;
         case reset:  /* call externally refined system-reset */
            reset_system();
            break;
         case debug:  /* activate debug mode */
            if (!debug_mode) {
               debug_mode=true;
            } break;
         default:
            printf("unimplemented instruction %#x\n",i);
            handle_error(INTERNAL_ERROR_INVALID_OPCODE);
      }
   goto end_inst;  /* normal instructions skip the call execution paths */
   nested_call:  /* common execution path for non-tail calls */
      {
         inst *next_word = (inst *) x;  /* was set by the call instructions that jumped here */
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
   tail_call:    /* common execution path for tail calls */
      {
         inst *next_word = (inst *) x;  /* was set by the call instructions that jumped here */
         if (debug_mode) {
            char * name = find_by_address(next_word);
            printf("tail calling: %s -> %d\n",name,debug_nest);
         }
         pc = next_word;
      }
      goto end_inst;
   end_inst:     /* end of instruction processing */
      (void) 0;
   }
}
