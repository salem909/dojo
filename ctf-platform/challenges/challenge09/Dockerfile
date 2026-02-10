FROM ctf-challenge-base:latest

COPY instructions.txt /challenge/instructions.txt
COPY runme.c /tmp/runme.c
COPY readflag.c /tmp/readflag.c

RUN gcc /tmp/runme.c -o /challenge/runme \
    && chown root:root /challenge/runme \
    && chmod 4755 /challenge/runme \
    && gcc /tmp/readflag.c -o /usr/local/bin/readflag \
    && chown root:root /usr/local/bin/readflag \
    && chmod 4755 /usr/local/bin/readflag \
    && rm /tmp/runme.c /tmp/readflag.c \
    && echo "FLAG{chal09-path-hijack}" > /flag \
    && chmod 400 /flag \
    && chown root:root /flag
