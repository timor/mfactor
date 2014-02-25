#include <stdio.h>


#include "interpreter.h"

void SystemInit() 
{}

int main(void)
{
  printf("libc running\n");
  inst p1[]={quit, emit, emit, emit, dup, dup, FIXNUM(42), lit};
  inst p2[]={quit, emit, truefalse, FIXNUM('f'), lit, FIXNUM('t'), lit, FIXNUM(0), lit};
  inst p3[]={quit, emit, truefalse, FIXNUM('f'), lit, FIXNUM('t'), lit, FIXNUM(1), lit};
  inst twostar[]={retsub,emit,emit,dup,FIXNUM(42),lit};
  inst onestar[]={retsub,emit,FIXNUM(42),lit};
  inst p4[]={quit,CALL(ifquot),CALL(twostar), lit, CALL(onestar), lit, FIXNUM(0),lit};
  interpreter((inst*)TBEGIN(p2));
  interpreter((inst*)TBEGIN(p3));
  interpreter((inst*)TBEGIN(p4));
  interpreter(&p1[sizeof(p1)/sizeof(inst)-1]);
  do {
    interpreter(NULL);
  } while(1);
}


