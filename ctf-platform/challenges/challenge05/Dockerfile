FROM ctf-challenge-base:latest

COPY instructions.txt /challenge/instructions.txt
COPY mystery.c /tmp/mystery.c
COPY readflag.c /tmp/readflag.c

RUN gcc /tmp/mystery.c -o /challenge/mystery \
    && chmod 755 /challenge/mystery \
    && gcc /tmp/readflag.c -o /usr/local/bin/readflag \
    && chown root:root /usr/local/bin/readflag \
    && chmod 4755 /usr/local/bin/readflag \
    && rm /tmp/mystery.c /tmp/readflag.c \
    && echo "FLAG{chal05-strings}" > /flag \
    && chmod 400 /flag \
    && chown root:root /flag
