/*
 * cuda-probe — report which CUDA driver API the resolvable libcuda.so.1 offers.
 *
 * MESA GPU images use it to decide whether NVIDIA's CUDA forward-compat
 * libraries are needed (see mesa-gpu-env.sh) and in mesa-gpu-check.
 * Shared file: keep identical in the five idss-mesa GPU image repos.
 *
 *   cuda-probe          -> "cuInit=0 cuda_driver_api=12.2 devices=1 lib=/usr/lib/..."
 *   cuda-probe --api    -> "12"   (major API version; prints nothing on failure)
 *
 * Exit status: 0 = cuInit succeeded and at least one device is visible,
 *              1 = libcuda loaded but no usable device, 2 = libcuda not loadable.
 *
 * Build: gcc -O2 -Wall -o cuda-probe cuda-probe.c -ldl   (depends only on glibc)
 */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdio.h>
#include <string.h>

typedef int (*cu_init_fn)(unsigned int);
typedef int (*cu_int_fn)(int *);

int main(int argc, char **argv)
{
    int api_only = argc > 1 && strcmp(argv[1], "--api") == 0;

    void *h = dlopen("libcuda.so.1", RTLD_NOW | RTLD_LOCAL);
    if (!h) {
        if (!api_only)
            printf("libcuda.so.1 not loadable: %s\n", dlerror());
        return 2;
    }

    cu_init_fn cu_init = (cu_init_fn)dlsym(h, "cuInit");
    cu_int_fn cu_version = (cu_int_fn)dlsym(h, "cuDriverGetVersion");
    cu_int_fn cu_count = (cu_int_fn)dlsym(h, "cuDeviceGetCount");
    if (!cu_init || !cu_version || !cu_count) {
        if (!api_only)
            printf("libcuda.so.1 is missing cuInit/cuDriverGetVersion/cuDeviceGetCount\n");
        return 2;
    }

    int version = 0, devices = 0;
    int rc = cu_init(0);
    cu_version(&version);
    if (rc == 0)
        cu_count(&devices);
    int ok = rc == 0 && devices > 0;

    if (api_only) {
        if (ok)
            printf("%d\n", version / 1000);
        return ok ? 0 : 1;
    }

    Dl_info info;
    const char *path = dladdr((void *)cu_init, &info) && info.dli_fname ? info.dli_fname : "?";
    printf("cuInit=%d cuda_driver_api=%d.%d devices=%d lib=%s\n",
           rc, version / 1000, (version % 1000) / 10, devices, path);
    return ok ? 0 : 1;
}
