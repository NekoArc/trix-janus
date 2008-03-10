# Copyright (C) 2007 Daniel De Graaf
# Released under the GNU Affero General Public License v3
package Network;
use SocketHandler;
use Persist 'SocketHandler';
use Carp qw(cluck);
use strict;
use warnings;

=head1 Network

Object representing a network

=over

=item $net->jlink()

The InterJanus object if the network is remote, or undef if local

=item $net->gid()

Globally unique ID for this network

=item $net->name()

The network ID for this network (short form)

=item $net->netname()

The human-readable name for this network (long form)

=item $net->numeric()

The unique numeric value for this network. May be deprecated at some time in the future.

=cut

my @jlink   :Persist(jlink)   :Get(jlink)   :Arg(jlink);
my @gid     :Persist(gid)     :Get(gid)     :Arg(gid);
my @name    :Persist(id)      :Get(name)    :Arg(id);
my @netname :Persist(netname) :Get(netname) :Arg(netname);
my @numeric :Persist(numeric) :Get(numeric) :Arg(numeric);
my @synced  :Persist(synced)  :Get(is_synced);

sub jname {
	my $net = $_[0];
	$name[$$net].'.janus';
}

sub lid {
	${$_[0]};
}

sub _init {
	my $net = $_[0];
	$gid[$$net] ||= $RemoteJanus::self->id().':'.$$net;
	&Debug::alloc($net, 1);
}

sub _set_name {
	$name[${$_[0]}] = $_[1];
}

sub _set_numeric {
	$numeric[${$_[0]}] = $_[1];
}

sub _set_netname {
	$netname[${$_[0]}] = $_[1];
}

sub to_ij {
	my($net,$ij) = @_;
	my $out = '';
	$out .= ' gid='.$ij->ijstr($net->gid());
	$out .= ' id='.$ij->ijstr($net->name());
	$out .= ' jlink='.$ij->ijstr($net->jlink() || $RemoteJanus::self);
	$out .= ' netname='.$ij->ijstr($net->netname());
	$out .= ' numeric='.$ij->ijstr($net->numeric());
	$out;
}

sub _destroy {
	my $net = $_[0];
	&Debug::alloc($net, 0, $netname[$$net]);
}

sub str {
	cluck "str called on a network";
	$_[0]->jname();
}

sub id {
	cluck "id called on a network";
	$_[0]->name();
}

&Janus::hook_add(
	LINKED => check => sub {
		my $act = shift;
		my $net = $act->{net};
		return undef unless $net->isa(__PACKAGE__);
		$synced[$$net] = 1;
		undef;
	}, NETSPLIT => act => sub {
		my $act = shift;
		my $net = $act->{net};
		my $msg = 'hub.janus '.$net->jname();
		my @clean;
		for my $nick ($net->all_nicks()) {
			next if $nick->homenet() ne $net;
			push @clean, +{
				type => 'QUIT',
				dst => $nick,
				msg => $msg,
				except => $net,
				netsplit_quit => 1,
				nojlink => 1,
			};
		}
		&Janus::insert_full(@clean);
		&Debug::info("Nick deallocation start");
		@clean = ();
		&Debug::info("Nick deallocation end");
		for my $chan ($net->all_chans()) {
			warn "Channel not on network!" unless $chan->is_on($net);
			push @clean, +{
				type => 'DELINK',
				dst => $chan,
				net => $net,
				netsplit_quit => 1,
				except => $net,
				reason => 'netsplit',
				nojlink => 1,
			};
		}
		&Janus::insert_full(@clean);
		&Debug::info("Channel deallocation start");
		@clean = ();
		&Debug::info("Channel deallocation end");
	},
);

1;
