FROM ctf-challenge-base:latest

COPY instructions.txt /challenge/instructions.txt
COPY check.c /tmp/check.c
COPY readflag.c /tmp/readflag.c

RUN gcc /tmp/check.c -o /challenge/check \
    && chmod 755 /challenge/check \
    && gcc /tmp/readflag.c -o /usr/local/bin/readflag \
    && chown root:root /usr/local/bin/readflag \
    && chmod 4755 /usr/local/bin/readflag \
    && rm /tmp/check.c /tmp/readflag.c \
    && echo "FLAG{chal10-debugging}" > /flag \
    && chmod 400 /flag \
    && chown root:root /flag
