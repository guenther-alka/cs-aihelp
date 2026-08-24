# ai_compile_check.pl -- compile-check the AI Helpdesk action.pl files
# (they are normally compiled inside admin.pl, so globals + stubs are declared here)
use strict;
use FindBin qw($RealBin);
use vars qw(%in %cfg %current %sys %zfs %disk $wpath $dpath $tpath $debug $t $sys);

(my $root = "$RealBin/..") =~ s{\\}{/}g;

# admin.pl context stubs
sub mylib_menue_system { }
sub load_lib { my ($lib) = @_; require "$root/data/menues/_lib/windows/$lib"; }
sub list2table { return '<table></table>'; }
sub log_end { }
sub mess { }
sub reload { }
sub exe { }
sub socket { }

my @files = (
  "$root/data/menues/10_System/05_Services/70_AI_Helpdesk/action.pl",
  "$root/data/menues/05_Help/50_AI_Helpdesk/action.pl",
);
for my $f (@files) {
    { my $ok = do $f;
      die "compile error in $f: $@" if $@;
      die "do failed for $f: $!" if (!$ok && $!); }
    print "compiled OK: $f\n";
}
print "ALL COMPILE OK\n";
