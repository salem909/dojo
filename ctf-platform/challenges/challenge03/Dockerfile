FROM ctf-challenge-base:latest

COPY instructions.txt /challenge/instructions.txt
COPY readflag.c /tmp/readflag.c

RUN echo 'export TOKEN="token-03-env"' > /etc/profile.d/chal03.sh \
    && gcc /tmp/readflag.c -o /usr/local/bin/readflag \
    && chown root:root /usr/local/bin/readflag \
    && chmod 4755 /usr/local/bin/readflag \
    && rm /tmp/readflag.c \
    && echo "FLAG{chal03-env-vars}" > /flag \
    && chmod 400 /flag \
    && chown root:root /flag
