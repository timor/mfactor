#include <stdio.h>


#include "interpreter.h"

void SystemInit() 
{}

int main(void)
{
  printf("libc running\n");
  inst prog[]={quit, emit, emit, emit, dup, dup, FIXNUM(42), lit};
  interpreter(&prog[sizeof(prog)/sizeof(inst)-1]);
  interpreter(NULL);
}


