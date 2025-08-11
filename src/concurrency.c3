module concurrency;

enum FutureState {
  FINISHED,
  PENDING,
  SLEEPING
}

typedef Future = inline IFuture{any};

macro Future anyfut() { return (Future){}; }

macro fut($Type) { return (IFuture{$Type}){}; }

module concurrency::future {FutRes};
import std::collections::list;
import std::thread;
import std::time;

alias FreeFn = fn void?(IFuture*);


struct Result {
  FutureState state;
  FutRes value;
}

interface IFuture {
  fn Result? poll();
  fn void? destroy();
}

macro IFuture IFuture.@done(self, Allocator #all, FutRes #val) {
  var fut_done = allocator::new(#all, FutDone{FutRes});

  fut_done.all = #all;
  fut_done.value = #val;
  return (IFuture) fut_done;
}

macro IFuture IFuture.@ch(self, Allocator #all, BufferedChannel{FutRes} #ch) {
  var fut_ch = allocator::new(#all, FutChReport{FutRes});

  fut_ch.all = #all;
  fut_ch.inner = self;
  fut_ch.ch = #ch;
  return (IFuture) fut_ch;
}

<*
  @require $assignable(#func, then::ThenFn{$Type, FutRes})
*>
macro IFuture.@then(self, Allocator #all, $Type, #func, any #args) {
  var fut_then = allocator::new(#all, FutThen{$Type, FutRes});

  fut_then.all = #all;
  fut_then.before = self;
  fut_then.then_fn = #func;
  fut_then.then_args = #args;
  return (IFuture{$Type}) fut_then;
}

macro Future IFuture.@wrap(self, Allocator #all) {
  var fut_any = allocator::new(#all, FutAny{FutRes});

  fut_any.all = #all;
  fut_any.fut = self;
  return (Future) fut_any;
}

struct FutAny (IFuture{any}) {
  Allocator all;
  IFuture fut;
}

fn Result{any}? FutAny.poll(&self) @dynamic {
  Result precise_res = self.fut.poll()!;
  return {
    .state = precise_res.state,
    .value = any_make(&precise_res.value, FutRes.typeid),
  };
}

fn void? FutAny.destroy(&self) @dynamic @inline {
  self.fut.destroy()!;
  allocator::free(self.all, self);
}

struct FutChReport (IFuture) {
  IFuture inner;
  channel::BufferedChannel {FutRes} ch;
  Allocator all;
}


fn Result? FutChReport.poll(&self) @dynamic {
  Result inner_res = self.inner.poll()!;
  if (inner_res.state == FINISHED) {
    self.ch.push(inner_res.value)!;
  }
  return inner_res;
}

fn void? FutChReport.destroy(&self) @dynamic {
  self.inner.destroy()!;
  allocator::free(self.all, self);
}

struct FutDone (IFuture) {
  Allocator all;
  FutRes value;
}

fn Result? FutDone.poll(&self) @dynamic {
  return {
    .state = FutureState.FINISHED,
    .value = self.value
  };
}

fn void? FutDone.destroy(&self) @dynamic {
  allocator::free(self.all, self);
}

module concurrency::future::then {FutRes, LeftRes};

alias ThenFn = fn IFuture{FutRes}(LeftRes, any);

struct FutThen (IFuture{FutRes}) {
  Allocator all;
  IFuture{LeftRes} before;
  IFuture{FutRes} then;
  ThenFn then_fn;
  any then_args;
}


// Basically... a port of tsoding's poll:
// https://github.com/tsoding/c3fut/blob/9aad0069592ed87f55e32955d79de9ecfa47db00/c3fut.c3#L100-L114
fn Result{FutRes}? FutThen.poll(&self) @dynamic {
  if (self.before != null) {
    Result{LeftRes} res = self.before.poll()!;
    if (res.state == FINISHED) {
      self.then = self.then_fn(res.value, self.then_args);
      self.before.destroy()!;
      self.before = null;
      return { .state = PENDING };
    }
    return { .state = res.state };
  } else {
    assert(self.then != null);
    return self.then.poll();
  }
}

fn void? FutThen.destroy(&self) @dynamic {
  self.then.destroy()!;
  allocator::free(self.all, self);
}

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

fn void? ThreadWorker.schedule(&self, IFuture{any} fut) @dynamic {
  self.mu.lock()!;
  // BUT WHY ;(
  self.futures.push(fut);
  self.mu.unlock()!;
}

import std::io;

// Ugly juggling of locking and unlocking because no expression blocks ;(
fn void? ThreadWorker.run(&self) @dynamic {
  @pool_init(&allocator::LIBC_ALLOCATOR, 100) {
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
  };
}
