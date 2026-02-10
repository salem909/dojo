FROM ctf-challenge-base:latest

COPY instructions.txt /challenge/instructions.txt
COPY webserver.py /challenge/webserver.py
COPY readflag.c /tmp/readflag.c

RUN chmod 755 /challenge/webserver.py \
    && gcc /tmp/readflag.c -o /usr/local/bin/readflag \
    && chown root:root /usr/local/bin/readflag \
    && chmod 4755 /usr/local/bin/readflag \
    && rm /tmp/readflag.c \
    && echo "FLAG{chal07-http-headers}" > /flag \
    && chmod 400 /flag \
    && chown root:root /flag
