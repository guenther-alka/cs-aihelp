#!/usr/bin/env perl
# install.pl -- install the cs-aihelp module into a napp-it cs installation.
# Usage: perl install.pl [/opt/csweb-gui]    (default: /opt/csweb-gui)
use strict;
use FindBin qw($RealBin);
use File::Path qw(make_path);
use File::Copy qw(copy);

(my $root = "$RealBin/..") =~ s{\\}{/}g;

my $VERSION = '0.5';
if (open my $fh, '<', "$root/VERSION") { chomp($VERSION = <$fh>); close $fh; }

my $target = shift // '/opt/csweb-gui';
$target =~ s{/+$}{};

my @files = (
  'data/wwwroot/cgi-bin/cs-aihelp.pl',
  'data/menues/_lib/windows/aihelplib.pl',
  'data/menues/05_Help/50_AI_Helpdesk/action.pl',
  'data/menues/10_System/05_Services/70_AI_Helpdesk/action.pl',
  'data/howto.ai/ai-helpdesk.info',
);

print "Installing cs-aihelp v$VERSION into $target\n\n";
for my $rel (@files) {
    my $src = "$root/$rel";
    my $dst = "$target/$rel";
    my ($dir) = $dst =~ m{(.*)/[^/]+$};
    make_path($dir) unless -d $dir;
    copy($src, $dst) or die "copy $src -> $dst failed: $!";
    print "  + $rel\n";
}

my $cfg = "$target/_cfg/cs-aihelp";
if (!-f $cfg) {
    make_path("$target/_cfg") unless -d "$target/_cfg";
    copy("$root/config/cs-aihelp.example", $cfg) or die "config copy failed: $!";
    print "  + _cfg/cs-aihelp (created from example)\n";
} else {
    print "  = _cfg/cs-aihelp (exists, left untouched)\n";
}

print "\nDone. Open the napp-it cs web-GUI and use:\n";
print "  Help > AI Helpdesk            (chat)\n";
print "  System > Services > AI Helpdesk  (settings)\n";
