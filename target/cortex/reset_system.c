/*****************************************************************************
*
* Klippel GmbH
* (c) Copyright 2014 Klippel GmbH Dresden
* ALL RIGHTS RESERVED.
*
******************************************************************************
*
* File Name: reset_system.c
*
* Created: 2014-04-04 17:56
*
* Author: Martin Bruestel<m.bruestel@klippel.de>
*
* Description: sysreset (PE)
*****************************************************************************/

#include "CPU.h"

void reset_system()
{
	Cpu_SystemReset();
}

