# Copyright (C) 2007 Daniel De Graaf
# Released under the Affero General Public License
# http://www.affero.org/oagpl.html
package ClientBot;
BEGIN { &Janus::load('LocalNetwork'); }
use Persist;
use Object::InsideOut 'LocalNetwork';
use Scalar::Util 'weaken';
use strict;
use warnings;
&Janus::load('Nick');

__PERSIST__
persist @sendq     :Field;
persist @nicks     :Field;
persist @self      :Field;
persist @kicks     :Field;
# $kicks[$$net]{$lid}{$channel} = time after which the nick will rejoin

__CODE__

my %fromirc;
my %toirc;

sub nick_sweep {
	my $p = shift;
	my $time = time;
	my $net = $p->{net};
	unless ($net) {
		delete $p->{repeat};
		return;
	}
	my $id = $net->id();
	my $normal = 1;
	unless ($Janus::nets{$id} && $Janus::nets{$id} eq $net) {
		delete $p->{repeat};
		$normal = 0;
	}
	my @out;
	NICK: for my $nn (keys %{$nicks[$$net]}) {
		my $nick = $nicks[$$net]{$nn};
		if (defined $nick) {
			my @nets = $nick->netlist();
			next NICK if $normal && @nets > 1;
			my $kicks = $kicks[$$net]{$nick->lid()};
			if ($normal && ref $kicks && %$kicks) {
				# rejoin the nick to timed out channels
				for my $cname (keys %$kicks) {
					next if $kicks->{$cname} > $time;
					push @out, +{
						type => 'JOIN',
						src => $nick,
						dst => $net->chan($cname),
					};
					delete $kicks->{$cname};
				}
			} else {
				delete $nicks[$$net]{$nn};
				delete $kicks[$$net]{$nick->lid()};
				push @out, +{
					type => 'QUIT',
					dst => $nick,
					msg => 'JanusTimeout: Not in any shared channels',
				};
			}
		} else {
			delete $nicks[$$net]{$nn};
		}
	}
	&Janus::insert_full(@out) if @out;
}

sub _init :Init {
	my $net = shift;
	$sendq[$$net] = [];

	my $sweeper = {
		repeat => 25,
		net => $net,
		code => \&nick_sweep,
	};
	weaken($sweeper->{net});
	&Janus::schedule($sweeper);
}

sub debug {
	print @_, "\n";
}

sub ignore { () }

sub intro :Cumulative {
	my($net,$param) = @_;
	$net->send(
		'USER mirror gamma * :Janus IRC Client',
		"NICK $param->{nick}",
	);
	$self[$$net] = $param->{nick};
}

sub cli_hostintro {
	my($net, $nname, $ident, $host, $gecos) = @_;
	my $nick = $nicks[$$net]{$nname};
	unless ($nick) {
		$nick = $net->item($nname);
		if ($nick) {
			$net->release_nick(lc $nname);
			&Janus::insert_full(+{
				type => 'RECONNECT',
				dst => $nick,
				net => $net,
				killed => 0,
				nojlink => 1,
			});
		}
		$nick = Nick->new(
			net => $net,
			ts => time,
			nick => $nname,
			info => {
				host => $host,
				vhost => $host,
				ident => $ident,
				name => ($gecos || 'MirrorServ Client'),
			},
			mode => {
				invisible => 1,
			},
		);
		$net->nick_collide($nname, $nick);
		$nicks[$$net]{$nname} = $nick;
		weaken($nicks[$$net]{$nname});
	}
	my @out;
	if ($nick->info('host') ne $host) {
		push @out, +{
			type => 'NICKINFO',
			src => $nick,
			dst => $nick,
			item => 'host',
			value => $host,
		};
	}
	if ($nick->info('ident') ne $ident) {
		push @out, +{
			type => 'NICKINFO',
			src => $nick,
			dst => $nick,
			item => 'ident',
			value => $ident,
		};
	}
	if (defined $gecos && $nick->info('name') ne $gecos) {
		push @out, +{
			type => 'NICKINFO',
			src => $nick,
			dst => $nick,
			item => 'name',
			value => $gecos,
		};
	}
	@out;
}

# parse one line of input
sub parse {
	my ($net, $line) = @_;
	my @out;
	debug '     IN@'.$net->id().' '. $line;
	$net->pong();
	my ($txt, $msg) = split /\s+:/, $line, 2;
	my @args = split /\s+/, $txt;
	push @args, $msg if defined $msg;
	if ($args[0] =~ /^:([^ !]+)!([^ @]+)@(\S+)/) {
		$args[0] = $1;
		push @out, $net->cli_hostintro($1, $2, $3);
	} elsif ($args[0] =~ /^:/) {
		$args[0] = undef;
	} else {
		unshift @args, undef;
	}
	my $cmd = $args[1];
	$cmd = $fromirc{$cmd} || $cmd;
	unless (ref $cmd) {
		debug "Unknown command '$cmd'";
		return ();
	}
	push @out, $cmd->($net,@args);
	@out;
}

sub send {
	my $net = shift;
	for my $act (@_) {
		if (ref $act) {
			my $type = $act->{type};
			next unless $toirc{$type};
			push @{$sendq[$$net]}, $toirc{$type}->($net,$act);
		} else {
			push @{$sendq[$$net]}, $act;
		}
	}
}

sub cmd1 { warn; () }
sub cmd2 { warn; () }

sub dump_sendq {
	my $net = shift;
	local $_;
	my $q = join "\n", @{$sendq[$$net]}, '';
	$q =~ s/\n+/\r\n/g;
	$sendq[$$net] = [];
	debug '    OUT@'.$net->id().' '.$_ for split /\r\n/, $q;
	$q;
}

# uncomment to force tags
#sub request_nick {
#	my($net, $nick, $reqnick) = @_;
#	&LocalNetwork::request_nick($net, $nick, $reqnick, 1);
#}

sub nicklen { 40 }

%toirc = (
	LINKREQ => sub {
		my($net,$act) = @_;
		return if $act->{linkfile};
		return if $act->{dlink} eq 'any';
		&Janus::insert_full(+{
			type => 'LINKREQ',
			dst => $act->{net},
			net => $net,
			slink => $act->{dlink},
			dlink => $act->{slink},
			override => 1,
		});
		();
	},
	LINK => sub {
		my($net,$act) = @_;
		my $chan = $act->{dst}->str($net);
		"JOIN $chan";
	},
	MSG => sub {
		my($net,$act) = @_;
		my $type = $act->{msgtype};
		return () unless $type eq 'PRIVMSG' || $type eq 'NOTICE';
		my $src = $act->{src};
		my $dst = $act->{dst};
		my $msg = $act->{msg};
		return () unless ref $src && $src->isa('Nick');
		return () unless ref $dst && ($dst->isa('Nick') || $dst->isa('Channel'));
		$src = $src->str($net);
		$dst = $dst->str($net);
		if ($msg =~ /^\001ACTION (.*?)\001?$/) {
			return "$type $dst :* $src $1";
		} else {
			return "$type $dst :<$src> $msg";
		}
	},
	KICK => sub {
		my($net,$act) = @_;
		my $nick = $act->{kickee};
		return () unless $nick->homenet()->id() eq $net->id();
		my $src = $act->{src};
		$src = ref $src && $src->isa('Nick') ? '<'.$src->str($net).'>' : '[?]';
		my $chan = $act->{dst}->str($net);
		my $nn = $nick->str($net);
		$kicks[$$net]{$nick->lid()}{$chan} = time + 15;
		"KICK $chan $nn :$src $act->{msg}";
	},
	PING => sub {
		"PING :poing";
	},
);

sub pm_not {
	my $net = shift;
	my $src = $net->item($_[0]) or return ();
	return () unless $src->isa('Nick');
	if ($_[2] eq $self[$$net]) {
		# PM to the bot
		my $msg = $_[3];
		if ($msg =~ s/^(\S+)\s//) {
			my $dst = $net->item($1);
			if (ref $dst && $dst->isa('Nick') && $dst->homenet()->id() ne $net->id()) {
				return +{
					type => 'MSG',
					src => $src,
					dst => $dst,
					msgtype => $_[1],
					msg => $msg,
				};
			}
		}
		if ($_[1] eq 'PRIVMSG') {
			$net->send("NOTICE $_[0] :Error: user not found. To message a user, prefix your message with their nick");
		}
		return ();
	}
	my $dst = $net->item($_[2]) or return ();
	return () unless $dst->isa('Channel');
	return +{
		type => 'MSG',
		src => $src,
		msgtype => $_[1],
		dst => $dst,
		msg => $_[3],
	};
}

sub kicked {
	my($net, $cname, $msg) = @_;
	my $chan = $net->chan($cname) or return ();
	my @out;
	for my $nick ($chan->all_nicks()) {
		next unless $nick->homenet()->id() eq $net->id();
		push @out, +{
			type => 'PART',
			src => $nick,
			dst => $chan,
			msg => 'Janus relay bot kicked: '.$msg,
		};
	}
	# try to rejoin - TODO enqueue the channel and delink it if this doesn't succeed in a little bit
	$net->send("JOIN $cname");
	@out;
}

%fromirc = (
	PRIVMSG => \&pm_not,
	NOTICE => \&pm_not,
	JOIN => sub {
		my $net = shift;
		return () if $_[0] eq $self[$$net];
		my $src = $net->nick($_[0]) or return ();
		return +{
			type => 'JOIN',
			src => $src,
			dst => $net->chan($_[2], 1),
		};
	},
	NICK => sub {
		my $net = shift;
		my $nick = $net->nick($_[0]) or return ();
		$nicks[$$net]{$_[2]} = delete $nicks[$$net]{$_[0]};
		weaken($nicks[$$net]{$_[2]});
		return +{
			type => 'NICK',
			src => $nick,
			dst => $nick,
			nick => $_[2],
		};
	},
	PART => sub {
		my $net = shift;
		if (lc $_[0] eq lc $self[$$net]) {
			# SAPART gives an auto-rejoin just to spite the people who think it's better than kick
			return $net->kicked($_[2], $_[3]);
		}
		my $src = $net->nick($_[0]) or return ();
		delete $kicks[$$net]{$src->lid()}{$_[2]};
		return +{
			type => 'PART',
			src => $src,
			dst => $net->chan($_[2], 1),
			msg => $_[3],
		};
	},
	KICK => sub {
		my $net = shift;
		if (lc $_[3] eq lc $self[$$net]) {
			return $net->kicked($_[2], $_[4]);
		}
		my $src = $net->nick($_[0]);
		my $chan = $net->chan($_[2]) or return ();
		my $victim = $net->nick($_[3]) or return ();
		delete $kicks[$$net]{$victim->lid()}{$_[2]};
		return +{
			type => 'KICK',
			src => $src,
			dst => $chan,
			kickee => $victim,
			msg => $_[4],
		};
	},
	QUIT => sub {
		my $net = shift;
		my $src = $net->nick($_[0]) or return ();
		delete $kicks[$$net]{$src->lid()};
		return +{
			type => 'QUIT',
			dst => $src,
			msg => $_[2],
		};
	},
	PING => sub {
		my $net = shift;
		$net->send("PONG :$_[2]");
		();
	},
	PONG => \&ignore,
	MODE => \&ignore,
	# misc
	'001' => sub {
		my $net = shift;
		return +{
			type => 'LINKED',
			net => $net,
			sendto => [ values %Janus::nets ],
		};
	},
	'002' => \&ignore,
	'003' => \&ignore,
	'004' => \&ignore,
	'005' => \&ignore,
	'042' => \&ignore,
	# intro (/lusers etc)
	251 => \&ignore,
	252 => \&ignore,
	253 => \&ignore,
	254 => \&ignore,
	255 => \&ignore,
	265 => \&ignore,
	266 => \&ignore,
	# MOTD
	372 => \&ignore,
	375 => \&ignore,
	376 => \&ignore,

	332 => \&ignore, # topic
	333 => \&ignore, # topic setter & ts

	315 => \&ignore, # end of /WHO
	352 => sub {
		my $net = shift;
#		:irc2.smashthestack.org 352 jmirror #test me admin.daniel irc2.smashthestack.org daniel Hr* :0 Why don't you ask me?
		my $chan = $net->chan($_[3]) or return ();
		my $n = $_[-1];
		$n =~ s/^\d+\s+//;
		return () if lc $_[7] eq lc $self[$$net];
		my @out = $net->cli_hostintro($_[7], $_[4], $_[5], $n);
		push @out, +{
			type => 'JOIN',
			src => $net->nick($_[7]),
			dst => $chan,
		};
		@out;
	},
	353 => \&ignore, # /NAMES list
	366 => sub { # end of /NAMES
		my $net = shift;
		$net->send("WHO $_[3]");
		();
	},
	422 => \&ignore, # MOTD missing
	433 => sub { # nick in use, try another
		my $net = shift;
		my $tried = $_[3];
		my $n = '';
		$n = $1 + 1 if $tried =~ s/_(\d*)$//;
		$tried .= '_'.$n;
		$net->send("NICK $tried");
		$self[$$net] = $tried;
		();
	},
	474 => sub { # we are banned
		my $net = shift;
		my $chan = $net->chan($_[3]) or return ();
		return +{
			type => 'DELINK',
			dst => $chan,
			net => $net,
		};
	},	
	482 => \&ignore, # kick failed (not enough information to determine which one
);

1;