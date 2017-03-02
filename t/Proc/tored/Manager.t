use Test2::Bundle::Extended -target => 'Proc::tored::Manager';
use Path::Tiny 'path';
use Data::Dumper;

my $dir = Path::Tiny->tempdir('temp.XXXXXX', CLEANUP => 1, EXLOCK => 0);
skip_all 'could not create writable temp directory' unless -w $dir;

my $term = $dir->child("$$.term");


sub counter($\$%) {
  my ($proc, $acc, %flag) = @_;
  my $backstop = 10;
  my $count = 0;

  return sub {
    $$acc = ++$count;

    if ($count >= $backstop) {
      diag "backstop reached ($backstop)";
      $proc->stop;
      return;
    }

    return $flag{$count}->($count)
      if $flag{$count};

    return 1;
  };
}

ok my $proc = $CLASS->new(name => 'proc-tored-test-' . $$, dir => "$dir"), 'new';
is $proc->running_pid, 0, 'running_pid is 0 with no running process';
ok !$proc->is_running, '!is_running';
ok !$proc->is_stopped, '!is_stopped';
ok !$proc->is_paused, '!is_paused';

subtest 'start/stop' => sub {
  $proc->clear_flags;
  ok !$proc->is_stopped, '!is_stopped';
  ok !$proc->start, '!start';
  ok $proc->stop, 'stop';
  ok $proc->is_stopped, 'is_stopped';
  ok $proc->start, 'start';
  ok !$proc->is_stopped, '!is_stopped';
};

subtest 'pause/resume' => sub {
  $proc->clear_flags;
  ok !$proc->is_paused, '!is_paused';
  ok !$proc->resume, '!resume';
  ok $proc->pause, 'pause';
  ok $proc->is_paused, 'is_paused';
  ok $proc->resume, 'resume';
  ok !$proc->is_paused, '!is_paused';
};

subtest 'run lock' => sub {
  $proc->clear_flags;
  my $path = $proc->pid_file->file;
  my $lock = $proc->lock;

  ok $lock, 'lock';
  ok $path->exists, 'pidfile created';
  is $proc->running_pid, $$, 'running_pid returns current pid';
  ok $proc->is_running, 'is_running true';
  ok !$proc->lock, '!lock while is_running';

  undef $lock;

  ok !$path->is_file, 'pidfile removed after guard out of scope';
  is $proc->running_pid, 0, 'running_pid returns 0 after guard out of scope';
  ok !$proc->is_running, 'is_running false after guard out of scope';
};

subtest 'start' => sub {
  $proc->clear_flags;
  my $acc = 0;
  my $counter = counter $proc, $acc, 3 => sub { 0 };
  ok $proc->service($counter), 'run service';
  is $acc, 3, 'service callback was called expected number of times';
  ok !$proc->is_stopped, '!is_stopped';
  ok !$proc->is_paused, '!is_paused';
};

subtest 'stop' => sub {
  $proc->clear_flags;
  my $acc = 0;
  my $counter = counter $proc, $acc, 3 => sub { $proc->stop };
  ok $proc->service($counter), 'run service';
  is $acc, 3, 'service self-terminates after being signalled';
};

subtest 'cooperation' => sub {
  $proc->clear_flags;
  my $acc = 0;
  my $recursive_start = 0;

  my $counter = counter $proc, $acc,
    1 => sub {
      $proc->service(sub { $recursive_start = 1; return 0 });
      return 0;
    };

  ok $proc->service($counter), 'run service';
  is $acc, 1, 'stopped when expected';
  ok !$recursive_start, 'second process did not start while first was running';
};

SKIP: {
  skip 'signals not supported for MSWin32' if $^O eq 'MSWin32';
  $proc = $CLASS->new(name => 'proc-tored-test-' . $$, dir => "$dir", trap_signals => ['INT']);
  $proc->clear_flags;

  subtest 'signals' => sub {
    $proc->clear_flags;
    my $acc = 0;
    my $counter = counter $proc, $acc,
      3  => sub { kill 'INT', $$ };

    ok $proc->service($counter), 'run service';
    is $acc, 3, 'stopped when expected';
  };
};

done_testing;
