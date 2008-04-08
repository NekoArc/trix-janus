# Copyright (C) 2007-2008 Daniel De Graaf
# Released under the GNU Affero General Public License v3
package RemoteNetwork;
use Network;
use Persist 'Network';
use strict;
use warnings;

sub all_nicks { 
	my $net = shift;
	grep { $_->is_on($net) } values %Janus::gnicks;
}

sub all_chans {
	my $net = shift;
	my %cbyid;
	$_->is_on($net) and $cbyid{$$_} = $_ for values %Janus::gchans;
	values %cbyid;
}

sub chan {
	my($net, $cname) = @_;
	my $kn = lc $net->gid() . $cname;
	$Janus::gchans{$kn};
}

sub send {
	my $net = shift;
	my $ij = $net->jlink();
	$ij->send(@_);
}

1;