#!/usr/bin/perl
# $Id: 01_socket_reuse.t,v 1.2 2005/04/15 15:49:56 rcaputo Exp $

# Test connection reuse.  Allocates a connection, frees it, and
# allocates another.  The second allocation should return right away
# because it is honored from the keep-alive pool.

use warnings;
use strict;
use lib qw(./mylib ../mylib);
use Test::More tests => 4;

sub POE::Kernel::ASSERT_DEFAULT () { 1 }

use POE;
use POE::Component::Client::Keepalive;

use TestServer;

use constant PORT => 49018;
TestServer->spawn(PORT);

POE::Session->create(
  inline_states => {
    _child   => sub { },
    _start   => \&start,
    _stop    => sub { },
    got_conn => \&got_conn,
  }
);

sub start {
  my $heap = $_[HEAP];

  $heap->{cm} = POE::Component::Client::Keepalive->new();

  $heap->{cm}->allocate(
    scheme  => "http",
    addr    => "127.0.0.1",
    port    => PORT,
    event   => "got_conn",
    context => "first",
  );
}

sub got_conn{
  my ($heap, $stuff) = @_[HEAP, ARG0];

  # The delete() ensures only one copy of the connection exists.
  my $connection = delete $stuff->{connection};
  my $which = $stuff->{context};
  ok(defined($connection), "$which request honored asynchronously");

  my $is_cached = $stuff->{from_cache};
  # Destroy the connection, freeing its socket.
  $connection = undef;

  if ($which eq 'first') {
    ok(not (defined ($is_cached)), "$which request not from cache");
    $heap->{cm}->allocate(
     scheme  => "http",
     addr    => "127.0.0.1",
     port    => PORT,
     event   => "got_conn",
     context => "second",
    );
  } elsif ($which eq 'second') {
    ok(defined $is_cached, "$which request from cache");
    TestServer->shutdown();
  }

}

POE::Kernel->run();
exit;
