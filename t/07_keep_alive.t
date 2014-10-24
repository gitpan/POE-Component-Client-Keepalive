#!/usr/bin/perl
# $Id: 07_keep_alive.t,v 1.1.1.1 2004/10/03 16:50:29 rcaputo Exp $

# Test keepalive.  Allocates a connection, frees it, waits for the
# keep-alive timeout, allocates an identical connection.  The second
# allocation should return a different connection.

use warnings;
use strict;
use lib qw(./mylib ../mylib);
use Test::More tests => 6;

sub POE::Kernel::ASSERT_DEFAULT () { 1 }

use POE;
use POE::Component::Client::Keepalive;

use TestServer;

use constant PORT => 49018;
TestServer->spawn(PORT);

POE::Session->create(
  inline_states => {
    _child            => sub { },
    _start            => \&start,
    _stop             => sub { },
    got_conn          => \&got_conn,
    got_first_conn    => \&got_first_conn,
    kept_alive        => \&keepalive_over,
    second_kept_alive => \&second_kept_alive,
  }
);

sub start {
  my $heap = $_[HEAP];

  $heap->{others} = 0;

  $heap->{cm} = POE::Component::Client::Keepalive->new(
    keep_alive => 1,
  );

  my $conn = $heap->{cm}->allocate(
    scheme  => "http",
    addr    => "127.0.0.1",
    port    => PORT,
    event   => "got_first_conn",
    context => "first",
  );

  ok(!defined($conn), "first connection request deferred");
}

sub got_first_conn {
  my ($kernel, $heap, $stuff) = @_[KERNEL, HEAP, ARG0];

  my $conn = $stuff->{connection};
  ok(defined($conn), "first request honored asynchronously");

  $kernel->delay(kept_alive => 2);
}

sub keepalive_over {
  my $heap = $_[HEAP];

  # The second and third requests should be deferred.  The first
  # connection won't be reused because it should have been reaped by
  # the keep-alive timer.

  my $second = $heap->{cm}->allocate(
    scheme  => "http",
    addr    => "127.0.0.1",
    port    => PORT,
    event   => "got_conn",
    context => "second",
  );

  ok(!defined($second), "second connection request deferred");

  my $third = $heap->{cm}->allocate(
    scheme  => "http",
    addr    => "127.0.0.1",
    port    => PORT,
    event   => "got_conn",
    context => "third",
  );

  ok(!defined($third), "third connection request deferred");
}

sub got_conn {
  my ($kernel, $heap, $stuff) = @_[KERNEL, HEAP, ARG0];

  my $conn  = $stuff->{connection};
  my $which = $stuff->{context};
  ok(defined($conn), "$which request honored asynchronously");

  if (++$heap->{others} == 2) {
    $kernel->delay(second_kept_alive => 2);
  }
}

sub second_kept_alive {
  $_[HEAP]->{cm}->shutdown();
  TestServer->shutdown();
}

POE::Kernel->run();
exit;
