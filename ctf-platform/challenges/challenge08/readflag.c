#include <stdio.h>
#include <string.h>

static const char *kToken = "token-08-script";

int main(int argc, char **argv) {
    char buf[256] = {0};

    if (argc > 1) {
        strncpy(buf, argv[1], sizeof(buf) - 1);
    } else {
        if (!fgets(buf, sizeof(buf), stdin)) {
            return 1;
        }
        size_t len = strcspn(buf, "\r\n");
        buf[len] = 0;
    }

    if (strcmp(buf, kToken) != 0) {
        fprintf(stderr, "bad token\n");
        return 1;
    }

    FILE *flag = fopen("/flag", "r");
    if (!flag) {
        perror("flag");
        return 1;
    }
    char out[256];
    if (fgets(out, sizeof(out), flag)) {
        printf("%s", out);
    }
    fclose(flag);
    return 0;
}
