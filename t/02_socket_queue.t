#!/usr/bin/perl
# $Id: 02_socket_queue.t 52 2006-03-29 15:26:30Z rcaputo $
# vim: filetype=perl

# Test connection queuing.  Set the max active connection to be really
# small (one in all), and then try to allocate two connections.  The
# second should queue.

use warnings;
use strict;
use lib qw(./mylib ../mylib);
use Test::More tests => 9;
use Errno qw(ECONNREFUSED);

sub POE::Kernel::ASSERT_DEFAULT () { 1 }

use POE;
use POE::Component::Client::Keepalive;

use constant PORT => 49018;
use constant UNKNOWN_PORT => PORT+1;
use TestServer;

TestServer->spawn(PORT);

POE::Session->create(
  inline_states => {
    _child          => sub { },
    _start          => \&start,
    _stop           => sub { },
    got_error       => \&got_error,
    got_first_conn  => \&got_first_conn,
    got_third_conn  => \&got_third_conn,
    got_fourth_conn => \&got_fourth_conn,
    got_timeout     => \&got_timeout,
    test_max_queue  => \&test_max_queue,
  }
);

sub start {
  my $heap = $_[HEAP];

  $heap->{cm} = POE::Component::Client::Keepalive->new(
    max_open => 1,
  );

  # Count the number of times test_max_queue is called.  When that's
  # 2, we actually do the test.

  $heap->{test_max_queue} = 0;

  # Make two identical tests.  They're both queued because the free
  # pool is empty at this point.

  {
    $heap->{cm}->allocate(
      scheme  => "http",
      addr    => "127.0.0.1",
      port    => PORT,
      event   => "got_first_conn",
      context => "first",
    );
  }

  {
    $heap->{cm}->allocate(
      scheme  => "http",
      addr    => "127.0.0.1",
      port    => PORT,
      event   => "got_first_conn",
      context => "second",
    );
  }
}

sub got_first_conn {
  my ($kernel, $heap, $stuff) = @_[KERNEL, HEAP, ARG0];

  my $conn = delete $stuff->{connection};
  my $which = $stuff->{context};
  ok(defined($conn), "$which connection honored asynchronously");
  if ($which eq 'first') {
    ok(not (defined ($stuff->{from_cache})), "$which not from cache");
  } else {
    ok(defined ($stuff->{from_cache}), "$which from cache");
  }

  $conn = undef;

  $kernel->yield("test_max_queue");
}

sub got_third_conn {
  my ($kernel, $heap, $stuff) = @_[KERNEL, HEAP, ARG0];

  my $conn = $stuff->{connection};
  my $which = $stuff->{context};
  ok(
    defined($stuff->{from_cache}),
    "$which connection request honored from pool"
  );

  $conn = undef;
}

# We need a free connection pool of 2 or more for this next test.  We
# want to allocate one of them, and then attempt to allocate a
# different connection.

sub test_max_queue {
  my ($kernel, $heap) = @_[KERNEL, HEAP];

  $heap->{test_max_queue}++;
  return unless $heap->{test_max_queue} == 2;

  $heap->{cm}->allocate(
    scheme  => "http",
    addr    => "127.0.0.1",
    port    => PORT,
    event   => "got_third_conn",
    context => "third",
  );

  $heap->{cm}->allocate(
    scheme  => "http",
    addr    => "127.0.0.1",
    port    => UNKNOWN_PORT,
    event   => "got_fourth_conn",
    context => "fourth",
  );
}

# This connection should fail, actually.

sub got_fourth_conn {
  my ($kernel, $heap, $stuff) = @_[KERNEL, HEAP, ARG0];

  my $conn = $stuff->{connection};
  ok(!defined($conn), "fourth connection failed (as it should)");

  ok($stuff->{function} eq "connect", "connection failed in connect");
  ok($stuff->{error_num} == ECONNREFUSED, "connection error ECONNREFUSED");

  my $lc_str = lc $stuff->{error_str};
  ok(
    $lc_str =~ /connection\s+refused/i,
    "error string: wanted(connection refused) got($lc_str)"
  );

  # Shut things down.
  TestServer->shutdown();
  $heap->{cm}->shutdown();
}

POE::Kernel->run();
exit;
