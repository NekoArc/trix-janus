# Copyright (C) 2007-2008 Daniel De Graaf
# Released under the GNU Affero General Public License v3
package Actions;
use strict;
use warnings;
use integer;

# item => Class
#   multiple classes space separated
#   '?'                must be first. Allows undef as value
#   '=expr='           must be first. Sets to eval(expr) if is undef
#   '@' or '%'         unblessed array or hash
#   '$'                checks that it is a string/number

=head1 Actions

Basic descriptions and checking of all internal janus actions

=head2 Internal Janus events

=over

=item NETLINK Sent when a connection to/from janus is initalized 

=item BURST Sent when a connection is ready to start syncing data

=item LINKED Sent when a connection is fully linked

=item NETSPLIT Disconnects a network from janus

=item RAW Internal network action; do not intercept or inspect

=back

=head2 Nick-Network motion events

=over

=item NEWNICK Nick has connected to its home net

=item CONNECT Janus nick introduced to a remote net

=item RECONNECT Janus nick reintroduced to a remote net

=item KILL Oper (or services) removes a remote nick from their network

=item QUIT Janus nick leaves home net, possibly involuntarily

=back

=head2 Nick-Channel motion events

=over

=item JOIN Nick joins a channel, possibly coming in with some modes (op)

=item PART Nick leaves a channel

=item KICK Nick involuntarily leaves a channel

=back

=head2 Channel state changes

=over

=item MODE Basic mode change

=over 

=item n nick access level

=item l list (bans)

=item v value (key)

=item s value-on-set (limit)

=item r regular (moderate)

=item t tristate (private/secret)

=back

=item TIMESYNC Channel creation timestamp modification

=item TOPIC Channel topic change

=back

=head2 Nick state changes

=over

=item NICK nickname change

=item UMODE nick mode change

=item NICKINFO nick metainformation change

=back

=head2 Communication

=over

=item MSG Overall one-to-some messaging

=item WHOIS remote idle queries

=item CHATOPS internetwork administrative communication

=back

=head2 Janus commands

=over

=item LINKREQ initial request to link a channel

=item LSYNC internal sync for InterJanus channel links

=item LINK final atomic linking and mode merge

=back

=head2 ClientBot commands

=over

=item IDENTIFY identify to the network

=back

=cut

my %spec = (
	JNETLINK => {
		net => 'RemoteJanus',
		sendto => '=$Janus::global= Janus @',
	},
	NETLINK => {
		net => 'Network',
		sendto => '=$Janus::global= Janus @',
	},
	LINKED => {
		net => 'Network',
		sendto => '=$Janus::global= Janus @',
	},
	JLINKED => {
		except => 'RemoteJanus',
		sendto => '=$Janus::global= Janus @',
	},
	BURST => {
		net => 'Network',
		sendto => '=$RemoteJanus::self= RemoteJanus @',
	},
	NETSPLIT => {
		net => 'Network',
		msg => '$',
		netsplit_quit => '?$',
		sendto => '=$Janus::global= Janus @',
	},
	JNETSPLIT => {
		net => 'RemoteJanus',
		msg => '$',
		netsplit_quit => '?$',
		sendto => '=$Janus::global= Janus @',
	},

	NEWNICK => {
		dst => 'Nick',
		sendto => '?',
	},
	CONNECT => {
		dst => 'Nick',
		net => 'Network',
	}, 
	RECONNECT => {
		dst => 'Nick',
		net => 'Network',
		killed => '$', # 1 = reintroduce, 0 = renick
	},
	KILL => {
		dst => 'Nick',
		msg => '?$',
		net => 'Network',
	},
	QUIT => {
		dst => 'Nick',
		msg => '$',
		killer => '?Nick Network',
		netsplit_quit => '?$',
	},

	JOIN => {
		src => 'Nick',
		dst => 'Channel',
		mode => '?%',
	},
	PART => {
		src => 'Nick',
		dst => 'Channel',
		msg => '?$',
	},
	KICK => {
		dst => 'Channel',
		kickee => 'Nick',
		msg => '$',
	},

	MODE => {
		dst => 'Channel',
		mode => '@',
		args => '@',
		dirs => '@',
	},
	TIMESYNC => {
		dst => 'Channel',
		wipe => '$',
		ts => '$',
		oldts => '$',
	},
	TOPIC => {
		dst => 'Channel',
		topicset => '$',
		topicts => '$',
		topic => '$',
		in_link => '?$',
	},

	NICK => {
		dst => 'Nick',
		nick => '$',
		nickts => '?$',
	},
	UMODE => {
		dst => 'Nick',
		mode => '@',
	},
	NICKINFO => {
		dst => 'Nick',
		item => '$',
		value => '?$',
	},

	MSG => {
		src => 'Nick Network',
		dst => 'Nick Channel',
		msgtype => '$',
		msg => '$ @',
		prefix => '?$',
	},
	WHOIS => {
		src => 'Nick',
		dst => 'Nick',
	},
	CHATOPS => {
		src => 'Nick',
		msg => '$',
	},

	LINKREQ => {
		dst => 'Network',
		net => 'Network',
		slink => '$',
		dlink => '$',
		linkfile => '?$',
		override => '?$',
		reqby => '?$',
		reqtime => '?$',
	},
	REQDEL => {
		snet => 'Network',
		dnet => 'Network',
		name => '$',
	},
	LOCKREQ => {
		src => 'Network',
		dst => 'Network Channel',
		name => '?$',
		lockid => '$',
	},
	LOCKACK => {
		src => 'RemoteJanus',
		dst => 'Network',
		chan => '?Channel',
		expire => '?$',
		lockid => '$',
	},
	LOCKED => {
		chan1 => 'Channel',
		chan2 => 'Channel',
	},
	UNLOCK => {
		dst => 'Channel',
		lockid => '$',
	},
	LINK => {
		dst => 'Channel',
		linkfile => '?$',
	},
	DELINK => {
		net => 'Network',
		netsplit_quit => '?$',
		'split' => '?Channel',
		reason => '$',
	},

	PING => {},
	PONG => {},
	IDENTIFY => {
		dst => 'Network',
		method => '?$',
		# add other args for manual methods?
	},
	REHASH => {
	},
	'INIT' => {
		args => '@', # program arguments
		except => '?',
	},
	RUN => { except => '?' },
	TSREPORT => {
		src => 'Nick',
	},

	XLINE => {
		dst => 'Network',
		ltype => '$',
		mask => '$',
		setter => '?$',
		expire => '$', # = 0 for permanent, = 1 for unset, = time else
		settime => '?$', # only valid if setting
		reason => '?$',  # only valid if setting
	},
);

my %default = (
	type => '$',
	src => '?Nick Network',
	dst => '?Nick Channel Network',
	except => '?Network RemoteJanus',
	sendto => '?@ Network RemoteJanus',
	nojlink => '?$',
	IJ_RAW => '?$',
);

for my $type (keys %spec) {
	for my $i (keys %default) {
		next if exists $spec{$type}{$i};
		$spec{$type}{$i} = $default{$i};
	}
}

&Janus::hook_add(ALL => validate => sub {
	my $act = shift;
	my $itm = $act->{type};
	my $check = $spec{$itm};
	unless ($check) {
		return undef if $itm eq 'RAW';
		&Debug::hook_err($act, "Unknown action type");
		return undef;
	}
	KEY: for my $k (keys %$check) {
		$act->{ERR} = "Fail: Key $k in $itm";
		$_ = $$check{$k};
		my $v = $act->{$k};
		if (s/^=(.*)=(\s+|$)//) {
			unless (defined $v) {
				$act->{$k} = eval $1;
				next KEY;
			}
		} elsif (s/^\?//) {
			next KEY unless defined $v;
		} else {
			return 1 unless defined $v;
		}
		for (split /\s+/) {
			next KEY if eval {
				/\$/ ? ('' eq ref $v) :
				/\@/ ? ('ARRAY' eq ref $v) :
				/\%/ ? ('HASH' eq ref $v) :
				$v->isa($_);
			};
		}
		return 1;
	}
	delete $act->{ERR};
	for my $k (keys %$act) {
		next if exists $check->{$k};
		&Debug::warn("unknown key $k in action $itm");
	}
	undef;
});

1;