#include "runtime.h"

void __attribute__((weak))
start_timer()
{
}

void __attribute__((weak))
end_timer(unsigned int *sec, unsigned int *usec)
{
  *sec=-1;
  *usec=-1;
}
