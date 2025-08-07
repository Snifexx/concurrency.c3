module concurrency;
typedef Future = inline IFuture{any};

enum FutureState {
  FINISHED,
  PENDING,
  SLEEPING
}

module concurrency::future {FutRes};
import std::collections::list;
import std::thread;

struct Result {
  FutureState state;
  FutRes value;
}

interface IFuture {
  fn Result? poll();
  fn void? destroy();
}


struct FutureAnyWrapper (IFuture{any}) {
  IFuture fut;
}

fn void FutureAnyWrapper.init(&self, IFuture fut) {
  self.fut = fut;
}

fn Result{any}? FutureAnyWrapper.poll(&self) @dynamic {
  Result precise_res = self.fut.poll()!;
  return {
    .state = precise_res.state,
    .value = any_make(&precise_res.value, FutRes.typeid),
  };
}

fn void? FutureAnyWrapper.destroy(&self) @dynamic @inline {
  self.fut.destroy()!;
}

struct FutureChannelWrapper (IFuture{any}) {
  IFuture{any} inner;
  channel::BufferedChannel {FutRes} ch;
}

fn Result{any}? FutureChannelWrapper.poll(&self) @dynamic {
  Result{any} inner_res = self.inner.poll()!;
  switch (inner_res.state) {
    case FINISHED:
      self.ch.push(*anycast(inner_res.value, FutRes))!;
      return {
        .state = FINISHED,
      };
    default:
      return inner_res;
  }
}

fn void? FutureChannelWrapper.destroy(&self) @dynamic {
  self.inner.destroy()!;
}

struct FutureDone (IFuture) {
  FutRes value;
}

fn Result? FutureDone.poll(&self) @dynamic {
  return {
    .state = FutureState.FINISHED,
    .value = self.value
  };
}

fn void? FutureDone.destroy(&self) @dynamic {}


module worker;
import concurrency;
import std::collections::list;
import std::thread;

interface Worker {
  fn bool done();
  fn void? schedule(IFuture{any} fut);
  fn void? run();
}

alias DestroyFn = fn void?(ThreadWorker*);
alias ThreadFuture = IFuture{any};

struct ThreadWorker (Worker) {
  List{IFuture{any}} futures;
  RecursiveMutex mu;
  bool stop;
  DestroyFn th_close_fn;
}

<*
  Initialize a worker in another thread.

  @param [&out] th : "Thread spawned from this worker"
*>
fn void? ThreadWorker.init(&self, Thread* th) {
  self.futures.init(&allocator::LIBC_ALLOCATOR, 8);
  self.mu.init()!;
  self.stop = false;
  self.th_close_fn = null;
  th.create(fn int(void* arg) {
    ThreadWorker* self = arg;
    if (catch self.run()) { return 1; }
    return 0;
  }, (void*) self)!;
}

<*
  Initialize a worker in another thread with a closing function called when the
  worker's loop is stopped.

  @param [&out] th : "Thread spawned from this worker"
  @param close_fn : "Cleaning function called at the end of the thread's life, when correctly stopped"
*>
fn void? ThreadWorker.init_with_close(&self, Thread* th, DestroyFn close_fn) @inline {
  self.init(th)!;
  self.th_close_fn = close_fn;
}

fn bool ThreadWorker.done(&self) @dynamic @inline {
  return self.stop;
}

// <*
//   Macro for type convenience. Automatically casts Future{x} into Future{any} for the
//   worker to use. See `void? ThreadWorker.schedule(&self, Future{any})`
//
//   @require (Future)#fut : "Argument must be a Future implementation"
//   @param #fut : "Future to schedule"
// *>
// macro void? ThreadWorker.@schedule(&self, #fut) {
//
// }

fn void? ThreadWorker.schedule(&self, IFuture{any} fut) @dynamic {
  self.mu.lock()!;
  // BUT WHY ;(
  self.futures.push(fut);
  self.mu.unlock()!;
}

import std::io;

// Ugly juggling of locking and unlocking because no expression blocks ;(
fn void? ThreadWorker.run(&self) @dynamic {
  self.mu.lock()!;
  while(!self.done()) {
    for (usz i = 0; i < self.futures.len();) {
      Result{any}? res = self.futures[i].poll();
      if (catch err = res) {
        self.mu.unlock()!;
        return err?;
      }
      switch (res.state) {
        case PENDING:
          i++;
        case SLEEPING:
          i++; // TODO Change to fit better uses
        case FINISHED:
          self.futures.swap(i, self.futures.len() - 1);
          fault err = @catch(self.futures.pop()!!.destroy());
          if (err) {
            self.mu.unlock()!;
            return err?;
          }
      }
    }

    self.mu.unlock()!;
    self.mu.lock()!;
  }
  self.mu.unlock()!;
  if (self.th_close_fn) {
    self.th_close_fn(self)!;
  }
}
