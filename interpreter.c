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

#define MEM_BASE 0x20000000

/* extern int putchar(int); */
/* extern int getchar(int); */

enum inst {
  dup,
  rot,
  drop,
  blah=900
};

typedef enum cell_type
{
  cell_fixnum = 0,
  cell_sequence,
  cell_string,					  /* value is  */
  cell_bignum,
  cell_code,
  cell_symbol
} cell_type;

typedef struct cell
{
  unsigned int value:29;
  cell_type type:3;
} cell;

#define FIXNUM(c) ((cell) {.type=cell_fixnum,.value=c})
  

typedef struct dict_entry
{
  cell * address;
  cell name;						  /* a string */
} dict_entry;

#define push(sp,val) (*(sp++)=val)
#define pop(sp) (*(--sp))
#define peek(sp) (*sp)

static void push_mem(cell *from, cell *to, cell *sp)
{
  ptrdiff_t diff = (to-from)*sizeof(cell);
  if (diff>0)
    memcpy(sp,from,diff);
  else
    memcpy(sp-diff,to,-diff);
}

void interpreter()
{
  static unsigned char iprog[] = {dup,dup,rot,(900)&0xff, (900>>8)&0xff};
  cell pstack[VM_PSTACK]={0};
  cell* psp = &pstack[0];
  cell rstack[VM_RSTACK]={0};
  cell* rsp = &rstack[0];
  cell cstack[VM_CSTACK]={0};
  cell* csp = &cstack[0];
#define next goto **(++pc)
  cell x;
  void *program[]={&&lit, (void*)'A', &&putchar, &&quit};
  void **pc = program;
  goto **pc;
  unsigned int sequence_counter=0;

drop:
  x = pop(psp);
  if (x.type != cell_fixnum)
    for (int i = 0; i < x.value; i++)
      (void) pop(psp);
  next;

dup:
  x = peek(psp);
  if (x.type == cell_fixnum)
    push(psp, x);
  else
    push_mem(psp-(x.value+1),psp,psp);
  next;

lit:
  push(psp,*((cell*)++pc));
  next;

putchar:
  putchar(pop(psp).value);
  fflush(stdout);
  next;

quit:
  return;
}


#endif
