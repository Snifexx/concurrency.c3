module test;
import concurrency;
import worker;
import std::thread;
import std::io;
import std::time;


fn void main(String[] args) {
  ThreadWorker wk;
  Thread th;
  Allocator all = &allocator::LIBC_ALLOCATOR;

  wk.init_with_close(&th, fn void?(ThreadWorker* self) {
    self.mu.destroy()!;
    self.futures.free();
    // Some sleep to showcase the detached worker thread finishing after
    // the main thread.
    thread::sleep(2 * time::SEC); 
  })!!;
  th.detach()!!;

  channel::BufferedChannel {char} ch;
  ch.init(all)!!;
  defer ch.destroy()!!;

  Future fut = concurrency::fut()
    .@done(all, (char)69)
    .@ch(all, ch);

  io::printn("Before scheduling.");
  wk.schedule(fut)!!;
  io::printn("After scheduling.");

  char res = ch.pop()!!;
  io::printn("Closed Channel!");
  ch.close()!!;

  wk.mu.@in_lock() {
    wk.stop = true;
  };
  io::printf("Result from future!: %d\n", res);

  thread::exit(0);
}
