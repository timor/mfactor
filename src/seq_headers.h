/* helper functions for working with sequence headers */

#ifndef SEQ_HEADERS_H
#define SEQ_HEADERS_H

#include "interpreter.h"

typedef unsigned char seq_header;
/* typedef unsigned char seq_type; */

#if NOINLINE
#define SEQ_INLINE static
#else
#define SEQ_INLINE static inline
#endif

/* fixed-width sequence element types */
/* SEQ_INLINE seq_type fe_element_type(seq_header h) */
/* { */
/*   return (h >> 2) & 0x7; */
/* } */

/* element sizes:
 * 0 -> 1 byte
 * 1 -> 2 bytes
 * 2 -> 3 bytes
 * 4 -> 5 bytes
 * ...
 * 7 -> 8 bytes
 * */

SEQ_INLINE unsigned int fe_element_size(seq_header h)
{
  return (h & 0x3)+1;
}

/* return size, without header, second argument is pointer to count byte*/
SEQ_INLINE unsigned int fe_seq_size(seq_header h, inst* count_ptr)
{
  return fe_element_size(h) * ((unsigned char)*count_ptr);
}


#endif
