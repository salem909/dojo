#include <stdio.h>

static const char *kHidden = "token-05-strings";

int main() {
    puts("nothing to see here");
    return kHidden[0] == 'x' ? 1 : 0;
}
