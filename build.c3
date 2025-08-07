module build;
import make3;

fn int main(String[] args) {
  CliEvent event = CliEvent.DEFAULT;
    // make3::default_cli_interpret(args);
  BuildCmd cmd;
  cmd.tinit({
    "c3c", "compile-run",
    "-o", "build/test",
    "src/*", "test/*"
  });
  // cmd.lib("libc");

  // BuildCmd test;
  // test.tinit({
  //   "echo", "TEST!"
  // });
  if (make3::@print_err(make3::@go_rebuild_urself(args))) return 1;
  switch (event) {
    // case TEST:
    //   if (make3::@print_err(make3::run(test.build()))) return 2;
    default:
      if (make3::@print_err(make3::run(cmd.build()))) return 2;
  }
	return 0;
}
