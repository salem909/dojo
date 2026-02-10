FROM ctf-challenge-base:latest

COPY instructions.txt /challenge/instructions.txt
COPY logs.txt /challenge/logs.txt
COPY readflag.c /tmp/readflag.c

RUN gcc /tmp/readflag.c -o /usr/local/bin/readflag \
    && chown root:root /usr/local/bin/readflag \
    && chmod 4755 /usr/local/bin/readflag \
    && rm /tmp/readflag.c \
    && echo "FLAG{chal08-scripting}" > /flag \
    && chmod 400 /flag \
    && chown root:root /flag
