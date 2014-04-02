#include <sys/stat.h>
 
enum {
  UART_FR_RXFE = 0x10,
  UART_FR_TXFF = 0x20,
  UART0_ADDR = 0x4000C000,
};
 
#define UART_DR(baseaddr) (*(unsigned int *)(baseaddr))
#define UART_FR(baseaddr) (*(((unsigned int *)(baseaddr))+6))
 
int _close(int file) {
  return 0;
}
 
int _fstat(int file, struct stat *st) {
  st->st_mode = S_IFCHR;
  return 0;
}
 
int _isatty(int file) {
  return 1;
}
 
int _lseek(int file, int ptr, int dir) {
  return 0;
}
 
int _open(const char *name, int flags, int mode) {
return -1;
}

int _write(int,char *, int);


int _read(int file, char *ptr, int len) {
  int todo;
  char *orig=ptr;
  if(len == 0)
    return 0;
  while(UART_FR(UART0_ADDR) & UART_FR_RXFE);
  *ptr++ = UART_DR(UART0_ADDR);
  for(todo = 1; todo < len; todo++) {
    if(UART_FR(UART0_ADDR) & UART_FR_RXFE) { break; }
    *ptr++ = UART_DR(UART0_ADDR);
  }
  /* serial echo */
  _write(0,orig,len);
  return todo;
}
 
register char * stack_ptr asm ("sp");

caddr_t _sbrk(int incr) {
  static char *heap_end = 0;
  extern char end asm ("end");   /* Defined by the linker */
  char *prev_heap_end;
  if (heap_end == 0) {
    heap_end = & end;
  }
  prev_heap_end = heap_end;
  if (heap_end + incr > stack_ptr) {
    /* Heap and stack collision */
    return (caddr_t)-1;
  }
  heap_end += incr;
  return (caddr_t) prev_heap_end;
}
 
int _write(int file, char *ptr, int len) {
  int todo;
  for (todo = 0; todo < len; todo++) {
    UART_DR(UART0_ADDR) = *ptr++;
  }
  return len;
}
