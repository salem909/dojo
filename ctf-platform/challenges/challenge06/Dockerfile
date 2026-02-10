FROM ctf-challenge-base:latest

COPY instructions.txt /challenge/instructions.txt
COPY encoded.txt /challenge/encoded.txt
COPY decoder.py /challenge/decoder.py
COPY readflag.c /tmp/readflag.c

RUN chmod 755 /challenge/decoder.py \
    && gcc /tmp/readflag.c -o /usr/local/bin/readflag \
    && chown root:root /usr/local/bin/readflag \
    && chmod 4755 /usr/local/bin/readflag \
    && rm /tmp/readflag.c \
    && echo "FLAG{chal06-crypto}" > /flag \
    && chmod 400 /flag \
    && chown root:root /flag
