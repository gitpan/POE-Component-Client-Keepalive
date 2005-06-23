#!/usr/bin/perl
# $Id: 04_free_each.t 17 2005-05-06 15:58:31Z martijn $

# Testing the bits that keep track of connections per connection key.

use warnings;
use strict;
use lib qw(./mylib ../mylib);
use Test::More tests => 6;

sub POE::Kernel::ASSERT_DEFAULT () { 1 }

use POE;
use POE::Component::Client::Keepalive;

use constant PORT => 49018;
use TestServer;

TestServer->spawn(PORT);

POE::Session->create(
  inline_states => {
    _start      => \&start,

    got_conn    => \&got_conn,
    got_error   => \&got_error,
    got_timeout => \&got_timeout,
    test_alloc  => \&test_alloc,
    and_free    => \&and_free,

    _child => sub { },
    _stop  => sub { },
  }
);

# Allocate two connections.  Wait for both to be allocated.  Free them
# both.

sub start {
  my $heap = $_[HEAP];

  $heap->{cm} = POE::Component::Client::Keepalive->new();

  {
    $heap->{cm}->allocate(
      scheme  => "http",
      addr    => "localhost",
      port    => PORT,
      event   => "got_conn",
      context => "first",
    );
  }

  {
    $heap->{cm}->allocate(
      scheme  => "http",
      addr    => "localhost",
      port    => PORT,
      event   => "got_conn",
      context => "second",
    );
  }
}

sub got_conn {
  my ($heap, $stuff) = @_[HEAP, ARG0];

  my $conn  = $stuff->{connection};
  my $which = $stuff->{context};

  ok(defined($conn), "$which connection created successfully");
  ok(not (defined ($stuff->{from_cache})), "$which not from cache");

  $heap->{conn}{$which} = $conn;

  return unless keys(%{$heap->{conn}}) == 2;

  # Free all heaped connections.
  delete $heap->{conn};

  # Give the server time to accept the connection.
  $_[KERNEL]->delay(test_alloc => 1);
}

# Allocate and free a third connection.  It's reused from the free
# pool.

sub test_alloc {
  my $heap = $_[HEAP];

  $heap->{cm}->allocate(
    scheme  => "http",
    addr    => "localhost",
    port    => PORT,
    event   => "and_free",
    context => "third",
  );
}

sub and_free {
	my ($heap, $stuff) = @_[HEAP, ARG0];

  my $conn  = delete $stuff->{connection};
  my $which = $stuff->{context};

  ok(defined($conn), "$which connection created successfully");
  is(
		$stuff->{from_cache}, 'immediate',
		"third connection honored from the pool"
	);

	# Free the connection first.
	$conn = undef;

  TestServer->shutdown();
  $heap->{cm}->shutdown();
}

POE::Kernel->run();
exit;
