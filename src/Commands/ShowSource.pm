# Copyright (C) 2008 Daniel De Graaf
# Released under the GNU Affero General Public License v3
package Commands::ShowSource;
use strict;
use warnings;

&Event::command_add({
	cmd => 'showsource',
	help => 'Shows lines of the janus source',
	section => 'Info',
	details => [
		"\002SHOWSOURCE\002 module line[-line]",
	],
	code => sub {
		my($src, $dst, $mod, $line) = @_;
		$mod =~ /([0-9A-Za-z:_*]+)/ or return &Janus::jmsg($dst, "Use: showsource module line");
		my $fn = "src/$1.pm";
		$fn =~ s#::#/#g;
		open my $f, $fn or return &Janus::jmsg($dst, "Cannot open module file");
		my($s,$e) = ($line =~ /(\d+)(?:-(\d+))?/);
		return &Janus::jmsg($dst, "Use: showsource module line") unless $s;
		$e ||= $s;
		for (1..($s-1)) {
			return unless defined <$f>;
		}
		$e = $s + 20 if $e > $s + 20;
		for ($s..$e) {
			my $l = <$f>;
			last unless defined $l;
			$l =~ s/[\r\n]//g;
			&Janus::jmsg($dst, $l);
		}
	},
});

1;