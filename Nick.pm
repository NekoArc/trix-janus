# Copyright (C) 2007 Daniel De Graaf
# Released under the GNU Affero General Public License v3
package Nick;
use strict;
use warnings;
use Persist;
use Scalar::Util 'weaken';

our($VERSION) = '$Rev$' =~ /(\d+)/;

=head1 Nick

Object representing a nick that exists across several networks

=over

=item $nick->gid()

Globally unique identifier for this nick. Format is currently jname:netid:nickid

=item $nick->homenet()

Home network object for this nick.

=item $nick->homenick()

String of the home nick of this user

=item $nick->ts()

Last nick-change timestamp of this user (to help determine collision resolution)

=cut

my @gid      :Persist(gid) :Get(gid);
my @homenet  :Persist(homenet) :Get(homenet);
my @homenick :Persist(homenick) :Get(homenick);
my @nets     :Persist(nets);
my @nicks    :Persist(nicks);
my @chans    :Persist(chans);
my @mode     :Persist(mode);
my @info     :Persist(info);
my @ts       :Persist(ts) :Get(ts);

my %initargs = (
	gid => '',
	net => '',
	nick => '',
	ts => '',
	info => '',
	mode => '',
);

sub _init {
	my($nick, $ifo) = @_;
	my $net = $ifo->{net};
	my $gid = $ifo->{gid} || $net->gid() . ':' . $$nick;
	$gid[$$nick] = $gid;
	$Janus::gnicks{$gid} = $nick;
	$homenet[$$nick] = $net;
	$homenick[$$nick] = $ifo->{nick};
	$nets[$$nick] = { $$net => $net };
	$nicks[$$nick] = { $$net => $ifo->{nick} };
	$ts[$$nick] = $ifo->{ts} || time;
	$info[$$nick] = $ifo->{info} || {};
	$mode[$$nick] = $ifo->{mode} || {};
	# prevent mode bouncing
	$mode[$$nick]{oper} = 1 if $mode[$$nick]{service};
	print "   NICK:$$nick $homenick[$$nick] allocated\n";
}

sub to_ij {
	my($nick, $ij) = @_;
	local $_;
	my $out = '';
	$out .= ' gid='.$ij->ijstr($gid[$$nick]);
	$out .= ' net='.$ij->ijstr($homenet[$$nick]);
	$out .= ' nick='.$ij->ijstr($homenick[$$nick]);
	$out .= ' ts='.$ij->ijstr($ts[$$nick]);
	$out .= ' mode='.$ij->ijstr($mode[$$nick]);
	$out .= ' info=';
	$out . $ij->ijstr($info[$$nick]);
}

sub _destroy {
	my $n = $_[0];
	print "   NICK:$$n $homenick[$$n] deallocated\n";
}

# send to all but possibly one network for NICKINFO
# send to home network for MSG
sub sendto {
	my($nick, $act, $except) = @_;
	if ($act->{type} eq 'MSG' || $act->{type} eq 'WHOIS') {
		return $homenet[$$nick];
	} elsif ($act->{type} eq 'CONNECT' || $act->{type} eq 'RECONNECT') {
		return $act->{net};
	} else {
		my %n = %{$nets[$$nick]};
		delete $n{$$except} if $except;
		return values %n;
	}
}

=item $nick->is_on($net)

return true if the nick is on the given network

=cut

sub is_on {
	my($nick, $net) = @_;
	return exists $nets[$$nick]{$$net};
}

=item $nick->netlist() 

return the list of all networks this nick is currently on

=cut

sub netlist {
	my $nick = $_[0];
	return values %{$nets[$$nick]};
}

=item $nick->has_mode($mode)

return true if the nick has the given umode

=cut

sub has_mode {
	my $nick = $_[0];
	return $mode[$$nick]->{$_[1]};
}

=item $nick->umodes()

returns the (sorted) list of umodes that this nick has set

=cut

sub umodes {
	my $nick = $_[0];
	return sort keys %{$mode[$$nick]};
}

=item $nick->all_chans()

returns the list of all channels the nick is on

=cut

sub all_chans {
	my $nick = $_[0];
	return values %{$chans[$$nick]};
}

=item $nick->jlink()

returns the InterJanus link if this nick is remote, or undef if it is local

=cut

sub jlink {
	my $net = $homenet[${$_[0]}];
	$net ? $net->jlink() : undef;
}

=item $nick->info($item)

information about this nick. Defined global info fields: 
	host ident ip name vhost away swhois

Locally, more info may be defined by the home Network; this should
be for use only by that local network

=cut

sub info {
	my $nick = $_[0];
	$info[$$nick]{$_[1]};
}

=item $nick->rejoin($chan)

Connecting to all networks that the given channel is on
(used when linking channels)

=cut

sub rejoin {
	my($nick,$chan) = @_;
	my $name = $chan->str($homenet[$$nick]);
	$chans[$$nick]{lc $name} = $chan;

	return if $nick->jlink();

	for my $net ($chan->nets()) {
		next if $nets[$$nick]{$$net};
		&Janus::append(+{
			type => 'CONNECT',
			dst => $nick,
			net => $net,
		});
	}
}

sub _part {
	my($nick,$chan) = @_;
	my $name = $chan->str($homenet[$$nick]);
	delete $chans[$$nick]->{lc $name};
	$nick->_netclean($chan->nets());
}

sub _netpart {
	my($nick, $net) = @_;	

	delete $nets[$$nick]{$$net};
	return if $net->jlink();
	my $rnick = delete $nicks[$$nick]{$$net};
	$net->release_nick($rnick, $nick);
	# this could be the last local network the nick was on
	# if so, we need to remove it from Janus::gnicks
	my $jl = $nick->jlink();
	return unless $jl;
	for my $net (values %{$nets[$$nick]}) {
		my $njl = $net->jlink();
		return unless $njl && $njl eq $jl;
	}
	delete $Janus::gnicks{$nick->gid()};
}

sub _netclean {
	my $nick = shift;
	return if $info[$$nick]{_is_janus};
	my $home = $nick->homenet();
	my %leave = @_ ? map { $_->lid() => $_ } @_ : %{$nets[$$nick]};
	delete $leave{$homenet[$$nick]->lid()};
	for my $cn (keys %{$chans[$$nick]}) {
		my $chan = $chans[$$nick]{$cn};
		unless ($chan->is_on($home)) {
			print "Found nick $$nick on delinked channel $$chan\n";
			delete $chans[$$nick]{$cn};
			next;
		}
		for my $net ($chan->nets()) {
			delete $leave{$net->lid()};
		}
	}
	for my $net (values %leave) {
		# This sending mechanism deliberately bypasses
		# the message queue because a QUIT is intended
		# to destroy the nick from all nets, not just one
		$net->send({
			type => 'QUIT',
			src => $nick,
			dst => $nick,
			msg => 'Left all shared channels',
		}) unless $net->jlink();
		$nick->_netpart($net);
	}
}

=item $nick->lid()

Locally unique ID for this nick (unique for the lifetime of the nick only)

=cut

sub lid {
	my $nick = $_[0];
	return $$nick;
}

=item $nick->str($net)

Get the nick's name on the given network

=cut

sub str {
	my($nick,$net) = @_;
	$nicks[$$nick]{$$net};
}

=back

=cut

&Janus::hook_add(
	CONNECT => check => sub {
		my $act = shift;
		my $nick = $act->{dst};
		my $net = $act->{net};
		return 1 if exists $nets[$$nick]{$$net};
		undef;
	}, CONNECT => act => sub {
		my $act = shift;
		my $nick = $act->{dst};
		my $net = $act->{net};
		$nets[$$nick]{$$net} = $net;
		return if $net->jlink();

		my $rnick = $net->request_newnick($nick, $homenick[$$nick], 0);
		$nicks[$$nick]->{$$net} = $rnick;
	}, RECONNECT => act => sub {
		my $act = shift;
		my $nick = $act->{dst};
		my $net = $act->{net};
		
		delete $act->{except};

		my $from = $act->{from} = $nicks[$$nick]{$$net};
		my $to = $act->{to} = $net->request_cnick($nick, $homenick[$$nick], 1);
		$nicks[$$nick]{$$net} = $to;
		
		if ($act->{killed}) {
			$act->{reconnect_chans} = [ values %{$chans[$$nick]} ];
		}
	}, NICK => check => sub {
		my $act = shift;
		my $old = lc $act->{dst}->homenick();
		my $new = lc $act->{nick};
		return 1 if $old eq $new;
		undef;
		# TODO Not transmitting case changes is the easiset way to do it
		# If this is ever changed: the local network's bookkeeping is easy
		# remote networks could have this nick tagged; they can untag but 
		# only if they can assure that it is impossible to be collided
	}, NICK => act => sub {
		my $act = $_[0];
		my $nick = $act->{dst};
		my $old = $homenick[$$nick];
		my $new = $act->{nick};

		$ts[$$nick] = $act->{nickts} if $act->{nickts};
		for my $id (keys %{$nets[$$nick]}) {
			my $net = $nets[$$nick]->{$id};
			next if $net->jlink();
			my $from = $nicks[$$nick]->{$id};
			my $to = $net->request_cnick($nick, $new);
			$nicks[$$nick]->{$id} = $to;
	
			$act->{from}->{$id} = $from;
			$act->{to}->{$id} = $to;
		}
	}, NICK => cleanup => sub {
		my $act = $_[0];
		my $nick = $act->{dst};
		$homenick[$$nick] = $act->{nick};
	}, NICKINFO => act => sub {
		my $act = $_[0];
		my $nick = $act->{dst};
		$info[$$nick]{$act->{item}} = $act->{value};
	}, UMODE => act => sub {
		my $act = $_[0];
		my $nick = $act->{dst};
		for my $ltxt (@{$act->{mode}}) {
			if ($ltxt =~ /\+(.*)/) {
				$mode[$$nick]->{$1} = 1;
			} elsif ($ltxt =~ /-(.*)/) {
				delete $mode[$$nick]->{$1};
			} else {
				warn "Bad umode change $ltxt";
			}
		}
	}, QUIT => cleanup => sub {
		my $act = $_[0];
		my $nick = $act->{dst};
		for my $id (keys %{$chans[$$nick]}) {
			my $chan = $chans[$$nick]->{$id};
			$chan->part($nick);
		}
		for my $id (keys %{$nets[$$nick]}) {
			my $net = $nets[$$nick]->{$id};
			next if $net->jlink();
			my $name = $nicks[$$nick]->{$id};
			$net->release_nick($name, $nick);
		}
		delete $chans[$$nick];
		delete $nets[$$nick];
		delete $homenet[$$nick];
		delete $Janus::gnicks{$nick->gid()};
	}, JOIN => act => sub {
		my $act = shift;
		my $nick = $act->{src};
		my $chan = $act->{dst};

		my $name = $chan->str($homenet[$$nick]);
		$chans[$$nick]->{lc $name} = $chan;

		return if $homenet[$$nick]->jlink();
		
		for my $net ($chan->nets()) {
			next if $nets[$$nick]{$$net};
			&Janus::insert_partial(+{
				type => 'CONNECT',
				dst => $nick,
				net => $net,
			});
		}
	}, PART => cleanup => sub {
		my $act = $_[0];
		my $nick = $act->{src};
		my $chan = $act->{dst};
		$nick->_part($chan);
	}, KICK => cleanup => sub {
		my $act = $_[0];
		my $nick = $act->{kickee};
		my $chan = $act->{dst};
		$nick->_part($chan);
	}, KILL => act => sub {
		my $act = shift;
		my $nick = $act->{dst};
		my $net = $act->{net};
		if ($nick->is_on($net) && !$net->jlink() && (!$act->{except} || $act->{except} ne $net)) {
			$net->send({
				type => 'QUIT',
				dst => $nick,
				msg => $act->{msg},
				killer => $act->{src},
			});
		}
		for my $chan (values %{$chans[$$nick]}) {
			next unless $chan->is_on($net);
			my $act = {
				type => 'KICK',
				src => ($act->{src} || $net),
				dst => $chan,
				kickee => $nick,
				msg => $act->{msg},
				except => $net,
				nojlink => 1,
			};
			$act->{sendto} = [ $chan->sendto($act, $net) ];
			&Janus::append($act);
		}
	}, KILL => cleanup => sub {
		my $act = shift;
		my $nick = $act->{dst};
		my $net = $act->{net};
		$nick->_netpart($net);
	},
);

1;
