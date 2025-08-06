module make3;
import std::io;
import std::os;
import std::collections;
import libc;

enum CliEvent: char {
  DEFAULT,
  TEST,
}

interface Cmd {
  fn String[] build();
}

fn CliEvent default_cli_interpret(String[] args) {
  if (args.len > 1 && args[1] == "test") {
    return CliEvent.TEST; 
  }
  return CliEvent.DEFAULT;
}

struct BuildCmd (Cmd) {
  List {String} args;
  Allocator all;
}

fn BuildCmd* BuildCmd.tinit(&self, String[] init) @inline @dynamic {
  return self.init(tmem, init);
}

fn BuildCmd* BuildCmd.init(&self, Allocator all, String[] init) @dynamic {
  self.all = all;
  self.args.init_with_array(all, init);
  return self;
}

fn BuildCmd* BuildCmd.shflib(&self, String lib) {
  self.args.push(string::format(self.all, "libs/%s", lib));
  return self;
}

fn BuildCmd* BuildCmd.lib(&self, String lib) {
  self.args.push("-l");
  self.args.push(lib);
  self.args.push("-L");
  self.args.push(string::format(self.all, "libs/%s", lib));
  self.args.push(string::format(self.all, "libs/%s/*", lib));
  return self;
}

fn String[] BuildCmd.build(&self) @dynamic {
  return self.args.to_array(self.all);
}

macro @print_err(#res) {
  if (catch err = #res) {
    io::printn(err);
    return true;
  }
  return false;
}

macro @go_rebuild_urself(#args) {
  return go_rebuild_urself(#args, $$FILEPATH, "make3.c3");
}

fn bool? should_rebuild(String binary_path, String[] listened_files) {
  Stat binary_stat;
  if (catch res = os::native_stat(&binary_stat, binary_path)) {
    // If binary does not exist it must rebuild
    io::print("Error getting stat for binary file: ");
    io::printn(res);
    io::printn("Hence should rebuild...");
    return true;
  }

  
  foreach (file : listened_files) {
    Stat listened_stat;
    if (catch res = os::native_stat(&listened_stat, file)) {
      io::print("Error getting stat for listened file: ");
      io::printn(res);
      return res?;
    }
    if (listened_stat.st_mtime > binary_stat.st_mtime) return true;
  }

  return false;
}

fn void? go_rebuild_urself(String[] args, String listened_file, String make3_path) {
  if (!should_rebuild(args[0], { listened_file, make3_path })!) return;

  io::printn("REBUILDING TRIGGERED!");

  SubProcess? process = process::create(
    { "c3c", "compile-run", listened_file, make3_path, "-o", args[0] },
    { .inherit_environment = true, .no_window = true, .inherit_stdio = true, }
  );

  if (catch err = process) {
    io::printfn("Rebuilding process failed: %s", err);
    return err?;
  }
  
  io::printn("REBUILDING MYSELF...");

  int res = process.join()!;

  if (res != 0) {
    io::printfn("Rebuilding failed with opcode %d", res);
    return;
  }

  os::exit(0);
}

fn int? run(String[] cmd) {
  SubProcess process = process::create(cmd, {
    .inherit_environment = true,
    .no_window = true,
    .inherit_stdio = true,
  })!;
  
  io::printn("Created build process");
  io::printn("Running build process...\n");

  int res = process.join()!;

  io::print("\nExecuted command '");
  io::print(cmd);
  io::print("' with exit code ");
  io::printn(res);

  return res;
}
