#include <stdio.h>
#include <string.h>

int main() {
    char buf[128] = {0};
    if (!fgets(buf, sizeof(buf), stdin)) {
        return 1;
    }
    buf[strcspn(buf, "\r\n")] = 0;
    if (strcmp(buf, "token-10-debug") == 0) {
        puts("ok");
    } else {
        puts("nope");
    }
    return 0;
}
