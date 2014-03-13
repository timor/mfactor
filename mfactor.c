#include <stdio.h>


#include "interpreter.h"
void SystemInit(void);

#pragma weak SystemInit
void SystemInit(void)
{}

int main(void)
{
  printf("libc running\n");
  /* inst p1[]={quit, emit, emit, emit, dup, dup, FIXNUM(42), lit}; */
  /* inst p2[]={quit, emit, truefalse, 'f', blit ,'t', blit, FIXNUM(0), lit}; */
  /* inst p3[]={quit, emit, truefalse, FIXNUM('f'), lit, FIXNUM('t'), lit, FIXNUM(1), lit}; */
  /* inst twostar[]={qend,emit,emit,dup,FIXNUM(42),lit}; */
  /* inst onestar[]={qend,emit,FIXNUM(42),lit}; */
  /* inst p4[]={quit,CALL(ifquot),CALL(twostar), lit, CALL(onestar), lit, FIXNUM(0),lit}; */
  /* inst loop[]={recurse,CALL(ifquot),  qend,sub,one,emit,dup,qstart,  qend,quit,drop,qstart,   eql,'0',blit,dup}; */
  /* inst p5[]={CALL(loop),'5',blit}; */
  /* interpreter((inst*)TBEGIN(p2)); */
  /* interpreter((inst*)TBEGIN(p3)); */
  /* interpreter((inst*)TBEGIN(p4)); */
  /* interpreter(&p1[sizeof(p1)/sizeof(inst)-1]); */
  /* interpreter((inst*)TBEGIN(p5)); */
  interpreter(NULL);
}


