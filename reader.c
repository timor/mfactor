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

/* for line reader mode */
#define LINESIZE 256
static char linebuffer[LINESIZE];
static unsigned int read_index = 1; /* current read index in line */
static unsigned int last_index = 0;				/* last accessible index in line */

#ifndef LINEREAD
	#define LINEREAD 1
#endif

static void readline()
{
	unsigned int i = 0;
	char c=0;
	for(i = 0; (i < LINESIZE) && (c != '\n') &&(c != '\r') ;)
		{
			c = getchar();
			linebuffer[i++]=c;
		}
	last_index=i-1;
	read_index=0;
}

char read_char()
{
	if (temp_char_p) {
		temp_char_p = false;
		return temp_char;
	} else {
#if LINEREAD
		if (read_index > last_index)
			readline();
		return linebuffer[read_index++];
#else
		return getchar();
#endif
	}
}

bool unread_char(char c)
{
	if (temp_char_p)
		return false;
	else {
		temp_char_p=true;
		temp_char=c;
		return true;
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

/* exception for double-quote */
/* return countedstring, but also generate terminating zero */
char * read_token()
{
	char c;
	unsigned int i=0;
	char *tokptr=token+1;
	skip_whitespace();
	bool nosep_token_found=false;
	while (!whitespacep(c=read_char())) {
		*tokptr++=c;
		i++;
		if (c == '"') {
			nosep_token_found = true;
			break;
		}
	}
	*tokptr++=0;
	if (!nosep_token_found)
		if (!unread_char(c))
			return NULL;
	token[0] = i;
	/* printf("got token: %s\n",token+1); */
	return token;
}
