// #include "timer.h"
#include <stdio.h>
#include <cuda.h>
#include <cuda_runtime.h>
#include "cublas_v2.h"
#include <pthread.h>

// ==========================================================================
// context boilerplate


/* TODO: this stuff can probably go away entirely */

// struct futStuff {
//   struct futhark_context_config *cfg;
//   struct futhark_context *ctx;
// };

// void* futInit() {
//   struct timer_t t;
//   timer_begin(&t, "futInit");

//   struct futhark_context_config *cfg = futhark_context_config_new();
//   timer_report_tick(&t, "futhark_context_config_new");

//   struct futhark_context *ctx = futhark_context_new(cfg);
//   timer_report_tick(&t, "futhark_context_new");

//   struct futStuff *result = malloc(sizeof(struct futStuff));
//   result->cfg = cfg;
//   result->ctx = ctx;
//   return (void *)result;
// }

// void futFinish(struct futStuff * futStuff) {
//   struct futhark_context_config *cfg = futStuff->cfg;
//   struct futhark_context *ctx = futStuff->ctx;

//   struct timer_t t;
//   timer_begin(&t, "futFinish");

//   futhark_context_free(ctx);
//   timer_report_tick(&t, "futhark_context_free");

//   futhark_context_config_free(cfg);
//   timer_report_tick(&t, "futhark_context_config_free");

//   futStuff->ctx = NULL;
//   futStuff->cfg = NULL;
//   free(futStuff);
// }

// ==========================================================================
// dMM boilerplate


/* TODO: inputs and outputs for leaf DMM, dimension info, etc. */
struct dMMPackage {
  // struct futStuff *futStuff;  /* won't need this */

  /* need to be specialized for DMM */
  float * a;
  float * b;
  float * output;
  uint64_t inputLen;

  /* these should stay */
  bool finished;
  pthread_t friends;
};

/* TODO: call cublas */
void* asyncdMMFunc(void* rawArg) {
  // struct timer_t t;
  // timer_begin(&t, "asyncdMMFunc");

  struct dMMPackage *pack = (struct dMMPackage *)rawArg;

  // futhark_entry_add(pack->futStuff->ctx,
  //   &(pack->output),
  //   &(pack->outputLen), 
  //   pack->a, 
  //   pack->b);
  float alpha = 1.0;
  float beta = 0.0;
  cublasHandle_t handle;
  cublasCreate(&handle);  
  cublasSgemm(handle, CUBLAS_OP_N, CUBLAS_OP_N, pack->inputLen, pack->inputLen, pack->inputLen, &alpha, (float*) pack->b, pack->inputLen, (float*) pack->a, pack->inputLen, &beta, (float*) pack->output, pack->inputLen);
  cublasDestroy(handle);
  // futhark_context_sync(pack->futStuff->ctx);
  // timer_report_tick(&t, "done");
  pack->finished = true; /* VERY IMPORTANT! */
  return NULL;
}


/* TODO: build the package, but otherwise shouldn't need to change much. 
 *
 * (NOTE: futhark_new_... is essentially a memcpy, these need to be replaced
 *  with stuff for cublas)
 */
extern "C" struct dMMPackage * 
dMMSpawn(
  void * a,
  void * b,
  int64_t inputLen)
{
  // struct futhark_context *ctx = futStuff->ctx;
  struct dMMPackage *pack = (dMMPackage*)malloc(sizeof(struct dMMPackage));
  // pack->futStuff = futStuff;
  // pack->a = futhark_new_u8_1d(ctx, a, inputLen);
  cudaMalloc(&(pack->a), inputLen*inputLen*sizeof(float));
  cudaMemcpy(pack->a, (float*)a, inputLen*inputLen*sizeof(float), cudaMemcpyHostToDevice);
  // pack->b = futhark_new_u8_1d(ctx, b, inputLen);
  cudaMalloc(&(pack->b),  inputLen*inputLen*sizeof(float));
  cudaMemcpy(pack->b, (float*)b,  inputLen*inputLen*sizeof(float), cudaMemcpyHostToDevice);
  // pack->outputLen = 0;
  cudaMalloc(&(pack->output),  inputLen*inputLen*sizeof(float));
  pack->inputLen = inputLen;
  pack->finished = false;

  if (0 != pthread_create(&(pack->friends), NULL, &asyncdMMFunc, pack)) {
    printf("ERROR: glue.c: futdMMSpawn: pthread_create failed\n");
    exit(1);
  }

  return pack;
}

/* TODO: probably doesn't need to change */
extern "C" uint8_t dMMPoll(struct dMMPackage *pack) {
  return pack->finished ? 1 : 0;
}

// int64_t futBigAddOutputSize(struct bigAddPackage *pack) {
//   // struct timer_t t;
//   // timer_begin(&t, "futPrimesOutputSize");

//   if (0 != pthread_join(pack->friend, NULL)) {
//     printf("ERROR: glue.c: futBigAddOutputSize: pthread_join failed\n");
//     exit(1);
//   }

//   // timer_report_tick(&t, "done");
//   return pack->outputLen;
// }

/* TODO: memcpy from GPU back to pack->output
 *
 * (NOTE: futhark_values is equivalent of this memcpy. needs to be replaced) */
extern "C" void dMMFinish(
  struct dMMPackage * pack,
  void * output)
{
  if (0 != pthread_join(pack->friends, NULL)) {
    printf("ERROR: glue.c: pthread_join failed\n");
    exit(1);
  }

  cudaMemcpy(output, pack->output, pack->inputLen*sizeof(float), cudaMemcpyDeviceToHost);
  cudaFree(pack->a);
  cudaFree(pack->b);
  cudaFree(pack->output);
  // futhark_values_u8_1d(pack->futStuff->ctx, pack->output, output);
  // futhark_free_u8_1d(pack->futStuff->ctx, pack->a);
  // futhark_free_u8_1d(pack->futStuff->ctx, pack->b);
  // futhark_free_u8_1d(pack->futStuff->ctx, pack->output);
  free(pack);

}
