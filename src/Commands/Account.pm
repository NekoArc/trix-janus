# Copyright (C) 2008 Daniel De Graaf
# Released under the GNU Affero General Public License v3
package Commands::Account;
use strict;
use warnings;

&Event::hook_add(
	INFO => Account => sub {
		my($dst, $acctid, $src) = @_;
		my $all = &Account::acl_check($src, 'useradmin') || $acctid eq &Account::has_local($src);
		if ($all) {
			&Janus::jmsg($dst, 'ACL: '.$Account::accounts{$acctid}{acl});
		}
	},
);
&Janus::command_add({
	cmd => 'account',
	help => 'Manages janus accounts',
	acl => 'useradmin',
	section => 'Account',
	details => [
		"\002ACCOUNT LIST\002               Lists all accounts",
		"\002ACCOUNT SHOW\002 account       Shows details on an account",
		"\002ACCOUNT CREATE\002 account     Creates a new (local or remote) account",
		"\002ACCOUNT DELETE\002 account     Deletes an account",
		"\002ACCOUNT GRANT\002 account acl  Grants an account access to the given command ACL",
		"\002ACCOUNT REVOKE\002 account acl Revokes an account's access to the given command ACL",
	],
	code => sub {
		my($src,$dst,$cmd,$acctid,@acls) = @_;
		$cmd = lc $cmd;
		$acctid = lc $acctid;
		if ($cmd eq 'create') {
			return &Janus::jmsg($dst, 'Account already exists') if $Account::accounts{$acctid};
			&Event::named_hook('ACCOUNT/add', $acctid);
			return &Janus::jmsg($dst, 'Done');
		} elsif ($cmd eq 'list') {
			&Janus::jmsg($dst, join ' ', sort keys %Account::accounts);
			return;
		}

		return &Janus::jmsg($dst, 'No such account') unless $Account::accounts{$acctid};
		if ($cmd eq 'show') {
			&Event::named_hook('INFO/Account', $dst, $acctid, $src);
		} elsif ($cmd eq 'delete') {
			&Event::named_hook('ACCOUNT/del', $acctid);
			&Janus::jmsg($dst, 'Done');
		} elsif ($cmd eq 'grant' && @acls) {
			my %acl;
			$acl{$_}++ for split / /, (&Account::get($acctid, 'acl') || '');
			for (@acls) {
				$acl{$_}++;
				unless (&Account::acl_check($src, $_)) {
					return &Janus::jmsg($dst, "You cannot grant access to permissions you don't have");
				}
			}
			&Account::set($acctid, 'acl', join ' ', sort keys %acl);
			&Janus::jmsg($dst, 'Done');
		} elsif ($cmd eq 'revoke' && @acls) {
			my %acl;
			$acl{$_}++ for split / /, (&Account::get($acctid, 'acl') || '');
			for (@acls) {
				delete $acl{$_};
				unless (&Account::acl_check($src, $_)) {
					return &Janus::jmsg($dst, "You cannot revoke access to permissions you don't have");
				}
			}
			&Account::set($acctid, 'acl', join ' ', sort keys %acl);
			&Janus::jmsg($dst, 'Done');
		} else {
			&Janus::jmsg($dst, 'See "help account" for the correct syntax');
		}
	}
}, {
	cmd => 'listacls',
	help => 'Lists all janus command ACLs',
	section => 'Info',
	code => sub {
		my($src,$dst) = @_;
		my %by_acl;
		for my $cmdname (sort keys %Event::commands) {
			my $cmd = $Event::commands{$cmdname};
			my $acl = $cmd->{acl};
			if ($acl) {
				$acl = 'oper' if $acl eq '1';
				$by_acl{$_} .= ' '.$cmdname for split /\|/, $acl;
			}
			$by_acl{$cmd->{aclchk}} .= ' '.$cmdname if $cmd->{aclchk};
		}
		&Janus::jmsg($dst, map { sprintf "\002%-10s\002\%s", $_, $by_acl{$_} } sort keys %by_acl);
	},
});

1;
