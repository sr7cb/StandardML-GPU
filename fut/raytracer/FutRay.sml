structure FutRay =
struct

  type fut_context = MLton.Pointer.t

  fun init () =
    (_import "fut_init" public : unit -> fut_context;) ()

  fun cleanup x =
    (_import "fut_cleanup" public : fut_context -> unit;) x

  type i64 = Int64.int
  type i32 = Int32.int
  type device = i64

  type prepared_scene = MLton.Pointer.t

  val prepare_rgbbox_scene =
    _import "prepare_rgbbox_scene" public : fut_context * i64 * i64 -> prepared_scene;

  val prepare_rgbbox_scene_free =
    _import "prepare_rgbbox_scene_free" public : fut_context * prepared_scene -> unit;

  type render_package = MLton.Pointer.t

  val render_spawn =
    _import "render_spawn" public : fut_context * device * prepared_scene * i64 * i64 * ( i32 array ) -> render_package;

  val render_poll = _import "render_poll" public : fut_context -> Word8.word;

  val render_finish = _import "render_finish" public : fut_context -> unit;

  fun render ctx prepared_scene output :
    (render_package, unit) ForkJoin.gpu_task =
    let
      val (data, start, len) = ArraySlice.base output

      fun spawn device =
        render_spawn (ctx, device, prepared_scene, start, len, data)
      fun poll x =
        (render_poll x = 0w1)
      fun finish x = render_finish x
    in
      ForkJoin.gpu {spawn = spawn, poll = poll, finish = finish}
    end

end
