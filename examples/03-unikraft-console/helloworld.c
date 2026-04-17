#include <stdio.h>
#include <unistd.h>

int main(void)
{
	puts("Hello World from Unikraft on Hetzner!");
	for (int i = 0; i < 15; i++) {
		putchar('.');
		fflush(stdout);
		sleep(1);
	}
	putchar('\n');
	return 0;
}
