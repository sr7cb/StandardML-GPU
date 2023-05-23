#include "futray/ray.h"
#include "timer.h"
#include <pthread.h>

// ==========================================================================
// context boilerplate

struct fut_context
{
  struct futhark_context_config *cfg1;
  struct futhark_context *ctx1;

  struct futhark_context_config *cfg2;
  struct futhark_context *ctx2;
};

void *fut_init()
{
  struct timer_t t;
  timer_begin(&t, "fut_init");

  struct futhark_context_config *cfg1 = futhark_context_config_new();
  struct futhark_context_config *cfg2 = futhark_context_config_new();
  timer_report_tick(&t, "futhark_context_config_new");

  futhark_context_config_set_device(cfg1, "#0");
  futhark_context_config_set_device(cfg2, "#1");
  timer_report_tick(&t, "futhark_context_config_set_device");

  struct futhark_context *ctx1 = futhark_context_new(cfg1);
  struct futhark_context *ctx2 = futhark_context_new(cfg2);
  timer_report_tick(&t, "futhark_context_new");

  struct fut_context *result = malloc(sizeof(struct fut_context));
  result->cfg1 = cfg1;
  result->cfg2 = cfg2;
  result->ctx1 = ctx1;
  result->ctx2 = ctx2;
  return (void *)result;
}

void fut_cleanup(struct fut_context *fut_context)
{
  struct futhark_context_config *cfg1 = fut_context->cfg1;
  struct futhark_context_config *cfg2 = fut_context->cfg2;
  struct futhark_context *ctx1 = fut_context->ctx1;
  struct futhark_context *ctx2 = fut_context->ctx2;

  struct timer_t t;
  timer_begin(&t, "fut_cleanup");

  futhark_context_free(ctx1);
  futhark_context_free(ctx2);
  timer_report_tick(&t, "futhark_context_free");

  futhark_context_config_free(cfg1);
  futhark_context_config_free(cfg2);
  timer_report_tick(&t, "futhark_context_config_free");

  fut_context->ctx1 = NULL;
  fut_context->ctx2 = NULL;
  fut_context->cfg1 = NULL;
  fut_context->cfg2 = NULL;
  free(fut_context);
}

// ==========================================================================
// prepare scene boilerplate

struct prepare_scene_pack
{
  int64_t height;
  int64_t width;
  struct futhark_opaque_scene *scene1;
  struct futhark_opaque_scene *scene2;
  struct futhark_opaque_prepared_scene *prepared_scene1;
  struct futhark_opaque_prepared_scene *prepared_scene2;
};


void do_prepare_rgbbox_scene(
  struct futhark_context *ctx,
  int64_t height,
  int64_t width,
  struct futhark_opaque_scene **scene,
  struct futhark_opaque_prepared_scene **prepared_scene)
{
  struct timer_t t;
  timer_begin(&t, "do_prepare_rgbbox_scene");

  futhark_entry_rgbbox(ctx, scene);
  futhark_context_sync(ctx);

  timer_report_tick(&t, "make scene");

  futhark_entry_prepare_scene(
      ctx,
      prepared_scene,
      height,
      width,
      *scene);
  futhark_context_sync(ctx);

  timer_report_tick(&t, "prepare scene");
}


void *prepare_rgbbox_scene(
    struct fut_context *fut_context,
    int64_t height,
    int64_t width)
{
  struct prepare_scene_pack *pack = malloc(sizeof(struct prepare_scene_pack));
  pack->height = height;
  pack->width = width;

  do_prepare_rgbbox_scene(fut_context->ctx1, height, width, &pack->scene1, &pack->prepared_scene1);
  do_prepare_rgbbox_scene(fut_context->ctx2, height, width, &pack->scene2, &pack->prepared_scene2);
  return pack;
}


void prepare_rgbbox_scene_free(
    struct fut_context *fut_context,
    struct prepare_scene_pack *pack)
{
  futhark_free_opaque_prepared_scene(fut_context->ctx1, pack->prepared_scene1);
  futhark_free_opaque_prepared_scene(fut_context->ctx2, pack->prepared_scene2);
  futhark_free_opaque_scene(fut_context->ctx1, pack->scene1);
  futhark_free_opaque_scene(fut_context->ctx2, pack->scene2);
  free(pack);
}

// ==========================================================================
// prepare scene and render boilerplate

struct render_pack
{
  struct fut_context *fut_context;
  int64_t device;
  bool finished;
  pthread_t friend;

  struct prepare_scene_pack *prepared_scene;
  int64_t start;
  int64_t len;

  int32_t *output;
};

void *render_threadfunc(void *rawArg)
{
  struct timer_t t;
  timer_begin(&t, "render_threadfunc");

  struct render_pack *pack = (struct render_pack *)rawArg;
  struct futhark_context *ctx =
    ( pack->device == 0 ?
      pack->fut_context->ctx1 :
      pack->fut_context->ctx2 );

  struct futhark_opaque_prepared_scene *prepared_scene =
    ( pack->device == 0 ?
      pack->prepared_scene->prepared_scene1 :
      pack->prepared_scene->prepared_scene2 );

  printf("SPAWN ON DEVICE %ld\n", pack->device);

  struct futhark_i32_1d *img;

  futhark_entry_render_pixels(
      ctx,
      &img,
      pack->prepared_scene->height,
      pack->prepared_scene->width,
      pack->start,
      pack->len,
      prepared_scene);
  futhark_context_sync(ctx);
  futhark_values_i32_1d(ctx, img, pack->output);
  futhark_free_i32_1d(ctx, img);

  timer_report_tick(&t, "render+move+free");

  pack->finished = true;
  return NULL;
}

struct render_pack *
render_spawn(
    struct fut_context *fut_context,
    int64_t device,
    struct prepare_scene_pack *prepared_scene,
    int64_t start,
    int64_t len,
    int32_t *output)
{
  struct render_pack *pack = malloc(sizeof(struct render_pack));
  pack->fut_context = fut_context;
  pack->device = device;
  pack->prepared_scene = prepared_scene;
  pack->start = start;
  pack->len = len;
  pack->finished = false;
  pack->output = output + start;

  if (0 != pthread_create(&(pack->friend), NULL, &render_threadfunc, pack))
  {
    printf("ERROR: glue.c: render_spawn: pthread_create failed\n");
    exit(1);
  }

  return pack;
}

uint8_t render_poll(struct render_pack *pack)
{
  return pack->finished ? 1 : 0;
}

void render_finish(struct render_pack *pack)
{
  if (0 != pthread_join(pack->friend, NULL))
  {
    printf("ERROR: glue.c: pthread_join failed\n");
    exit(1);
  }
  free(pack);
}