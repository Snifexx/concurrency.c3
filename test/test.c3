module test;
import concurrency;
import concurrency::future::then;
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

  channel::BufferedChannel {String} result_ch;
  result_ch.init(all)!!;
  defer result_ch.destroy()!!;

  Future fut = concurrency::fut(char)
    .@done(all, 69)
    .@ch(all, ch)
    .@then(all, String, fn(it, arg) {
      BufferedChannel{String} result_ch = *(BufferedChannel{String}*)arg;
      Allocator all = &allocator::LIBC_ALLOCATOR;

      return concurrency::fut(String)
        .@done(all, string::format(all, "String from then thread: %d", it))
        .@ch(all, result_ch);
    }, &result_ch)
    .@wrap(all);
  

  io::printn("Before scheduling.");
  wk.schedule(fut)!!;
  io::printn("After scheduling.");

  char res = ch.pop()!!;
  io::printn("Closed Channel!");
  ch.close()!!;

  String ress = result_ch.pop()!!;
  io::printn("Closed Last Channel!");
  result_ch.close()!!;

  wk.mu.@in_lock() {
    wk.stop = true;
  };
  io::printf("Result from first future: %d\n", res);
  io::printf("Result from finished future: \"%s\"\n", ress);

  thread::exit(0);
}
