# ai_compile_check.pl -- compile-check the AI Helpdesk action.pl files
# (they are normally compiled inside admin.pl, so globals + stubs are declared here)
use strict;
use FindBin qw($RealBin);
use vars qw(%in %cfg %current %sys %zfs %disk $wpath $dpath $tpath $debug $t $sys);

# Portable: repo layout (tests/ sibling of data/) on CI, fallback to the
# dev box's csweb-gui tree when run from C:\opt\testbase.
(my $root = "$RealBin/..") =~ s{\\}{/}g;
my $base = (-d "$root/data/howto.ai") ? "$root/data" : 'C:/opt/csweb-gui/data';

# admin.pl context stubs
sub mylib_menue_system { }
sub load_lib { my ($lib) = @_; require "$base/menues/_lib/windows/$lib"; }
sub list2table { return '<table></table>'; }
sub log_end { }
sub mess { }
sub reload { }
sub exe { }
sub socket { }

my @files = (
  "$base/menues/12_AI_Helpdesk/action.pl",
  "$base/menues/05_Help/00_AI_Helpdesk/action.pl",
);
for my $f (@files) {
    { my $ok = do $f;
      die "compile error in $f: $@" if $@;
      die "do failed for $f: $!" if (!$ok && $!); }
    print "compiled OK: $f\n";
}
print "ALL COMPILE OK\n";
