/* Reinicia com um "motivo" (ex.: recovery, download), como o "adb reboot <motivo>" do Android.
 * reboot(2) com LINUX_REBOOT_CMD_RESTART2: o kernel Samsung repassa o texto ao bootloader. */
#include <unistd.h>
#include <sys/syscall.h>
#include <linux/reboot.h>
int main(int argc, char **argv) {
    sync();
    return syscall(SYS_reboot, LINUX_REBOOT_MAGIC1, LINUX_REBOOT_MAGIC2, LINUX_REBOOT_CMD_RESTART2, argc > 1 ? argv[1] : "");
}
