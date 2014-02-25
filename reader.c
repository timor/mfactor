/*****************************************************************************
*
*
******************************************************************************
*
* File Name: reader.c
*
* Created: 2014-02-25 11:31
*
* Author: timor <timor.dd@googlemail.com>
*
* Description: implementation of simplest token reader
*****************************************************************************/
#include "reader.h"
#include <stdbool.h>
#include <stdio.h>

static char temp_char;
static bool temp_char_p = false;
static char token[MAX_TOKEN_SIZE];


char read_char()
{
	if (temp_char_p) {
		temp_char_p = false;
		return temp_char;
	} else {
		return getchar();
	}
}
int unread_char(char c)
{
	if (temp_char_p)
		return -1;
	else {
		temp_char_p=true;
		temp_char=c;
		return 0;
	}
}

static bool whitespacep(char c) {
  return
	  c == ' ' ||
	  c == '	' ||
	  c == 10 ||
	  c == 13;
}

static unsigned int skip_whitespace(void)
{
	char c;
	unsigned int skipped;
	while (whitespacep(c=read_char()))
		skipped+=1;
	unread_char(c);
	return skipped;
}

char * read_token()
{
	char c;
	char *tokptr=token;
	skip_whitespace();
	while (!whitespacep(c=read_char())) {
		*tokptr++=c;
	}
	*tokptr++=0;
	if (unread_char(c) != 0)
		return NULL;
	else return token;
}
