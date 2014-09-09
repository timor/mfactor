/*****************************************************************************
******************************************************************************
*
* File Name: reentry.h
*
* Created: 2014-07-16 10:27
*
* Author: timor <timor.dd@googlemail.com>
*
* Description: support functions for handling reentrancy
*****************************************************************************/
#ifndef __REENTRY_H
#define __REENTRY_H

/* lower priority to allow higher priorized instances to run */
	#define ALLOW_REENTRY() Cpu_SetBASEPRI(0)
/* raise priority again */
	#define DISALLOW_REENTY(prio) Cpu_SetBASEPRI(prio)
#endif
