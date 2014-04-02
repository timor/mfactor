/* linux implementation for runtime */

#include "runtime.h"

#include <time.h>

static struct timespec saved_ts;

static struct timespec diff(struct timespec start, struct timespec end)
{
  struct timespec temp;
	if ((end.tv_nsec-start.tv_nsec)<0) {
		temp.tv_sec = end.tv_sec-start.tv_sec-1;
		temp.tv_nsec = 1000000000+end.tv_nsec-start.tv_nsec;
	} else {
		temp.tv_sec = end.tv_sec-start.tv_sec;
		temp.tv_nsec = end.tv_nsec-start.tv_nsec;
	}
	return temp;
}

void start_timer()
{
  struct timespec t;
  clock_gettime(CLOCK_REALTIME,&t);
  saved_ts=t;
}

void end_timer(long int *sec, long int *usec)
{
  struct timespec t,d;
  clock_gettime(CLOCK_REALTIME,&t);
  d=diff(saved_ts, t);
  *sec=d.tv_sec;
  *usec=d.tv_nsec/1000;
}
