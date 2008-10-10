# Copyright (C) 2008 Daniel De Graaf
# Released under the GNU Affero General Public License v3
package Account;
use strict;
use warnings;
use Persist;

our %accounts;

&Janus::save_vars(accounts => \%accounts);

sub acl_check {
	my($nick, $acl) = @_;
	local $_;
	my @accts;
	my $selfid = $nick->info('account:'.$RemoteJanus::self->id);
	my %has = (
		oper => $nick->has_mode('oper'),
	);

	if ($accounts{$selfid}) {
		push @accts, $accounts{$selfid};
	}

	for my $ij (values %Janus::ijnets) {
		my $id = $ij->id;
		my $login = $nick->info('account:'.$id) or next;
		push @accts, $accounts{$id.':'.$login} if $accounts{$id.':'.$login};
	}

	for my $acct (@accts) {
		$has{user}++;
		next unless $acct->{acl};
		$has{$_}++ for split /\s+/, $acct->{acl};
	}
	return 1 if $has{'*'};
	for my $itm (split /\|/, $acl) {
		return 1 if $has{$itm};
	}
}

sub chan_access_chk {
	my($nick, $chan, $acl, $errs) = @_;
	my $net = $nick->homenet;
	unless ($chan->homenet == $net) {
		&Janus::jmsg($errs, "This command must be run from the channel's home network");
		return 0;
	}
	return 1 if acl_check($nick, 'oper');
	if (($acl eq 'link' || $acl eq 'create') && $net->param('oper_only_link')) {
		&Janus::jmsg($errs, 'You must be an IRC operator to use this command');
		return 0;
	}
	return 1 if $chan->has_nmode(owner => $nick);
	&Janus::jmsg($errs, "You must be a channel owner to use this command");
	return 0;
}

sub has_local {
	my $nick = shift;
	my $selfid = $nick->info('account:'.$RemoteJanus::self->id);
	return '' unless $selfid && defined $accounts{$selfid};
	$selfid;
}

sub get {
	my($nick, $item) = @_;
	my $id = ref $nick ? $nick->info('account:'.$RemoteJanus::self->id) : $nick;
	return undef unless $id && $accounts{$id};
	return $accounts{$id}{$item};
}

sub set {
	my($nick, $item, $value) = @_;
	my $id = ref $nick ? $nick->info('account:'.$RemoteJanus::self->id) : $nick;
	return 0 unless $id && $accounts{$id};
	$accounts{$id}{$item} = $value;
	1;
}

&Event::hook_add(
	ACCOUNT => add => sub {
		my $acctid = shift;
		$Account::accounts{$acctid} = {};
	},
	ACCOUNT => del => sub {
		my $acctid = shift;
		delete $Account::accounts{$acctid};
	},
#	NICKINFO => check => sub {
#		my $act = shift;
#	},
);

1;
