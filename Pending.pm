package Pending; {
use Object::InsideOut;
use strict;
use warnings;
use InterJanus;
use Socket6;

my @buffer :Field;
my @delegate :Field;
my @peer :Field :Arg(peer);

sub _init :Init {
	my $net = shift;
	my($port,$addr) = unpack_sockaddr_in6 $peer[$$net];
	$addr = inet_ntop AF_INET6, $addr;
	print "Pending connection from $addr:$port\n";
}

sub id {
	my $net = shift;
	'PEND#'.$$net;
}

sub parse {
	my($pnet, $line) = @_;
	my $rnet = $delegate[$$pnet];
	return $rnet->parse($line) if $rnet;

	push @{$buffer[$$pnet]}, $line;
	if ($line =~ /SERVER (\S+)/) {
		my $rnet;
		for my $id (keys %Conffile::netconf) {
			my $nconf = $Conffile::netconf{$id};
			if ($nconf->{server} && $nconf->{server} eq $1) {
				&Janus::delink($Janus::nets{$id}, 'Replaced by new connection') if $Janus::nets{$id};
				my $type = $nconf->{type};
				$rnet = eval "use $type; return ${type}->new(id => \$id)";
				next unless $rnet;
				print "Shifting new connection to $type network $id\n";
				$rnet->intro($nconf, 1);
				&Janus::link($rnet);
				last;
			}
		}
		my $q = delete $Janus::netqueues{$pnet->id()};
		if ($rnet) {
			$delegate[$$pnet] = $rnet;
			$$q[3] = $rnet;
			$Janus::netqueues{$rnet->id()} = $q;
			for my $l (@{$buffer[$$pnet]}) {
				&Janus::in_socket($rnet, $l);
			}
		}
	} elsif ($line eq 'InterJanus 0.1') {
		my $q = delete $Janus::netqueues{$pnet->id()};
		my $ij = InterJanus->new();
		print "Shifting new connection to InterJanus link\n";
		$ij->intro();
		$$q[3] = $ij;
		$Janus::netqueues{$ij->id()} = $q;
	}
	();
}

sub dump_sendq { '' }

} 1;
