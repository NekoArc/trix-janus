# Copyright (C) 2007-2008 Nima Gardideh
# Copyright (C) 2007-2009 Daniel De Graaf
# Released under the GNU Affero General Public License v3
package Commands::ClientUtils;
use strict;
use warnings;

Event::command_add({
	cmd => 'botnick',
	help => 'Changes the nick of a ClientBot',
	section => 'Network',
	syntax => '<network> <newnick>',
	acl => 'botnick',
	api => '=replyto localnet $',
	code => sub {
		my($dst,$net,$nick) = @_;
		return Janus::jmsg($dst, "Network must be a ClientBot.") unless $net->isa('Server::ClientBot');
		$net->send("NICK $nick");
		Janus::jmsg($dst, 'Done');
	}
}, {
	cmd => 'forceid',
	help => 'Forcibly tries to identify a ClientBot to services',
	section => 'Network',
	syntax => '<network>',
	acl => 'forceid',
	api => '=replyto localnet',
	code => sub {
		my($dst, $net) = @_;
		return Janus::jmsg($dst, "Network must be a ClientBot.") unless $net->isa('Server::ClientBot');
		if ($net->param('nspass') || $net->param('qauth') || $net->param('x3acct')) {
			Janus::jmsg($dst, 'Done');
		} else {
			Janus::jmsg($dst, "Network has no identify method configured");
			return;
		}
		Event::append(+{
			type => 'IDENTIFY',
			dst => $net,
		});
}, {
	cmd => 'ghost',
	help => 'Ghosts and reclaims the nickname of the bot on a network',
	section => 'Network',
	syntax => '<network>',
	acl => 'ghost',
	api => '=replyto localnet',
	code => sub {
		my($dst, $net) = @_;
		return Janus::jmsg($dst, "Network must be a ClientBot.") unless $net->isa('Server::ClientBot');
		if ($net->param('nspass')) {
			$net->send("PRIVMSG NickServ :GHOST $net->param('nick') $net->param('nspass')");
			$net->send("NICK $net->param('nick')");
			# Let's identify again
			$net->send("PRIVMSG NickServ :IDENTIFY $net->param('nspass')");
			Janus::jmsg($dst, 'Done');
		}
		if ($net->param('x3acct')) {
			$net->send("PRIVMSG AuthServ :GHOST $net->param('nick')");
			$net->send("NICK $net->param('nick')");
			# X3 expects us to be logged into the account to ghost, so no need to auth again
			Janus::jmsg($dst, 'Done');	
		}
		if ($net->param('qauth')) {
			Janus::jmsg($dst, 'Q does not have the ability to ghost nicknames!');		
		} else {
			Janus::jmsg($dst, "Network has no identify (and hence no ghost) method configured");
			return;
		}
	},
	},
});

1;
