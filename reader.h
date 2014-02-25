/*****************************************************************************
*
* Klippel GmbH
* (c) Copyright 2014 Klippel GmbH Dresden
* ALL RIGHTS RESERVED.
*
******************************************************************************
*
* File Name: reader.h
*
* Created: 2014-02-25 11:29
*
* Author: Martin Bruestel<m.bruestel@klippel.de>
*
* Description: helper for reading, should be replaced by mfactor def if too large
*****************************************************************************/
#ifndef __READER_H
#define __READER_H


#ifndef MAX_TOKEN_SIZE
#define MAX_TOKEN_SIZE 64
#endif

#include <stdbool.h>

char read_char(void);
bool unread_char(char);
char *read_token(void);


#endif
