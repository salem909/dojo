FROM ctf-challenge-base:latest

COPY instructions.txt /challenge/instructions.txt
COPY emit_token.sh /challenge/emit_token.sh
COPY readflag.c /tmp/readflag.c

RUN chmod 755 /challenge/emit_token.sh \
    && gcc /tmp/readflag.c -o /usr/local/bin/readflag \
    && chown root:root /usr/local/bin/readflag \
    && chmod 4755 /usr/local/bin/readflag \
    && rm /tmp/readflag.c \
    && echo "FLAG{chal04-fd-redir}" > /flag \
    && chmod 400 /flag \
    && chown root:root /flag
