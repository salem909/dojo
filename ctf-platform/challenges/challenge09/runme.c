#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

int main() {
    char *args[] = {"helper", NULL};
    execvp("helper", args);
    perror("execvp");
    return 1;
}
