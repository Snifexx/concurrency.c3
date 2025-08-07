module test;
import concurrency;
import worker;
import std::thread;
import std::io;


fn void main(String[] args) {
  ThreadWorker wk;
  Thread th;
  wk.init_with_close(&th, fn void?(ThreadWorker* self) {
    self.mu.destroy()!;
    self.futures.free();
  })!!;
  th.detach()!!;

  channel::BufferedChannel {char} ch;
  ch.init(&allocator::LIBC_ALLOCATOR)!!;
  defer ch.destroy()!!;

  FutureAnyWrapper{char} inner;
  inner.init(&&(FutureDone{char}) { .value = 69 });

  FutureChannelWrapper{char} fut = {
    .inner = &inner,
    .ch = ch,
  };

  channel::BufferedChannel {String} ch2;
  ch2.init(&allocator::LIBC_ALLOCATOR)!!;
  defer ch2.destroy()!!;

  FutureAnyWrapper{String} inner2;
  inner2.init(&&(FutureDone{String}) { .value = "Niggers" });

  FutureChannelWrapper{String} fut2 = {
    .inner = &inner2,
    .ch = ch2,
  };

  io::printn("Before scheduling.");
  wk.schedule(&fut)!!;
  wk.schedule(&fut2)!!;
  io::printn("After scheduling.");

  char res = ch.pop()!!;
  ch.close()!!;
  String res2 = ch2.pop()!!;
  ch2.close()!!;
  wk.mu.@in_lock() {
    wk.stop = true;
  };
  io::printf("Result from future!: %d\n", res);
  io::printf("Result from future!: %s\n", res2);

  Future futanari;
  io::printn(futanari.hello());

  thread::exit(0);
}
