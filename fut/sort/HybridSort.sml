structure HybridSort =
struct

  fun cpuOnlySort xs =
    if Seq.length xs < 1000 then
      Quicksort.sort Int64.compare xs
    else
      let
        val half = Seq.length xs div 2
        val left = Seq.take xs half
        val right = Seq.drop xs half
      in
        Merge.merge Int64.compare
          (ForkJoin.par (fn _ => cpuOnlySort left, fn _ => cpuOnlySort right))
      end


  fun gpuOnlySort ctx xs =
    ForkJoin.choice {cpu = fn _ => Util.die "uh oh", gpu = FutSort.sort ctx xs}


  fun sort ctx (xs: Int64.int Seq.t) =
    if Seq.length xs < 1000 then
      Quicksort.sort Int64.compare xs
    else
      let
        val half = Seq.length xs div 2
        val left = Seq.take xs half
        val right = Seq.drop xs half
        val (left', right') = ForkJoin.par (fn _ => sort ctx left, fn _ =>
          sortChoose ctx right)
      in
        Merge.merge Int64.compare (left', right')
      end

  and sortChoose ctx xs =
    if Seq.length xs >= 10000 then
      ForkJoin.choice {cpu = fn _ => sort ctx xs, gpu = FutSort.sort ctx xs}
    else
      sort ctx xs

end