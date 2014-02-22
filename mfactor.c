#include <stdio.h>


#include "interpreter.h"

void SystemInit() 
{}

int main(void)
{
  printf("libc running\n");
  inst p1[]={quit, emit, emit, emit, dup, dup, FIXNUM(42), lit};
  interpreter(&p1[sizeof(p1)/sizeof(inst)-1]);
  interpreter(NULL);
}


