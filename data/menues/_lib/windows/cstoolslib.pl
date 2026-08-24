# =============================================================================
# cstoolslib.pl -- central CS tools registry + GitHub download (System > CS Tools)
# (c) napp-it.org 2026
#
# cs-aihelp / cs-sleeper are NOT bundled in napp-it cs; their daemon binaries
# are downloaded from the GitHub release and installed KEEPING the OS
# structure: data/cs_server/tools/<tool>/<platform>.<arch>/<tool>[.exe]
# (legacy flat installs at data/cs_server/tools/<tool>[.exe] are still found).
# This keeps csweb-gui/data portable: after copying it to another OS, the
# matching <platform>.<arch> binary is resolved there (and can be fetched
# with "Download newest" from the CS Tools menu if missing).
# =============================================================================

use strict;
use vars qw($wpath $tpath);
use HTTP::Tiny;
use JSON::PP qw(decode_json);
use File::Copy qw(copy);
use File::Path qw(make_path remove_tree);

################  registry: every entry needs a GitHub release with assets.
# kind = 'tar'  -> assets "<asset>-<platform>.<arch>.tar.gz" (archive root
#                  "<platform>.<arch>/<asset>[.exe]")
# kind = 'raw'  -> assets "<asset>-<assetPlatform>-<arch>[.exe]" (raw binary)
# tok           -> optional map: detected platform => asset platform token
#                  (cs-stream uses 'windows', cs-freeze4snap is linux-only)
sub cstools_registry {
    return [
        { key => 'aihelp',  name => 'cs-aihelp (AI Helpdesk)',
          repo => 'guenther-alka/cs-aihelp',  asset => 'cs-aihelp',  subdir => 'cs-aihelp',
          module => 1, kind => 'tar',
          desc => 'AI Helpdesk Go daemon -- AI core, /ask, Level 2 exec proposer.' },
        { key => 'sleeper', name => 'cs-sleeper (disk spin-down)',
          repo => 'guenther-alka/cs-sleeper', asset => 'cs-sleeper', subdir => 'cs-sleeper',
          module => 0, kind => 'tar',
          desc => 'Disk spin-down / wake-up daemon (System > Power).' },
        { key => 'sync', name => 'cs-sync (realtime sync)',
          repo => 'guenther-alka/cs-sync', asset => 'cs-sync', subdir => 'cs-sync',
          module => 0, kind => 'tar',
          desc => 'Realtime sync service (System > Services > Realtime Sync).' },
        { key => 'send', name => 'cs-send (mail / notify)',
          repo => 'guenther-alka/cs-send', asset => 'cs-send', subdir => 'cs-send',
          module => 0, kind => 'tar',
          desc => 'Notification / mail helper.' },
        { key => 'stream', name => 'cs-stream (event stream)',
          repo => 'guenther-alka/cs-stream', asset => 'cs-stream', subdir => 'cs-stream',
          module => 0, kind => 'raw', tok => { mswin => 'windows' },
          desc => 'Event stream service.' },
        { key => 'freeze4snap', name => 'cs-freeze4snap',
          repo => 'guenther-alka/cs-freeze4snap', asset => 'cs-freeze4snap', subdir => 'cs-freeze4snap',
          module => 0, kind => 'raw', tok => { linux => 'linux' },
          desc => 'Filesystem freeze for snapshots (Linux only).' },
    ];
}

sub cstools_entry {
    my ($key) = @_;
    for my $e (@{cstools_registry()}) { return $e if $e->{key} eq $key; }
    return undef;
}

# asset platform token for the detected platform ('' = no asset for this OS)
sub cstools_asset_platform {
    my ($e, $platform) = @_;
    return ($e->{tok} ? ($e->{tok}{$platform} // '') : $platform);
}

################  platform detection -> (platform, arch, ext)
sub cstools_platform {
    my $os = lc($^O);
    my $platform = 'linux';
    $platform = 'mswin'   if $os =~ /mswin|win32|cygwin/;
    $platform = 'solaris' if $os =~ /solaris/;
    $platform = 'freebsd' if $os =~ /freebsd/;
    $platform = 'darwin'  if $os =~ /darwin/;
    if ($os =~ /solaris/) {
        my $o = `uname -o 2>/dev/null`;
        $platform = 'illumos' if defined $o && $o =~ /illumos/i;
    }
    my $arch = 'amd64';
    my $m = `uname -m 2>/dev/null`;
    $arch = 'arm64' if defined $m && $m =~ /aarch64|arm64/i;
    if ($platform eq 'mswin' && (($ENV{PROCESSOR_ARCHITECTURE} // '') =~ /ARM/i)) {
        $arch = 'arm64';
    }
    my $ext = ($platform eq 'mswin') ? '.exe' : '';
    return ($platform, $arch, $ext);
}

################  robust HTTPS: HTTP::Tiny -> PowerShell (Win) / curl-wget (Unix)
# Some installs lack working HTTPS in the bundled HTTP::Tiny (e.g. a broken
# Net::SSLeay on Windows); fall back to the system downloader.
sub _cstools_base {
    my $w = (defined $wpath && $wpath ne '') ? $wpath : '/opt/csweb-gui';
    return (defined $tpath && $tpath ne '') ? $tpath : "$w/tmp";
}

# (ok, content) -- for small responses (GitHub API JSON)
sub cstools_https_get {
    my ($url, $timeout) = @_;
    $timeout ||= 60;
    my $u = HTTP::Tiny->new(timeout => $timeout, verify_SSL => 1);
    my $r = $u->get($url, { headers => { 'User-Agent' => 'cs-tools', 'Accept' => 'application/vnd.github+json' } });
    if (!$r->{success}) {
        $u = HTTP::Tiny->new(timeout => $timeout, verify_SSL => 0);
        $r = $u->get($url, { headers => { 'User-Agent' => 'cs-tools', 'Accept' => 'application/vnd.github+json' } });
    }
    return (1, $r->{content}) if $r->{success};
    my $tw = _cstools_base();
    make_path($tw);
    my $tmp = "$tw/cstool_http.tmp";
    if (cstools_https_save($url, $tmp, $timeout)) {
        my $c = '';
        if (open(my $fh, '<:raw', $tmp)) { local $/; $c = <$fh>; close $fh; }
        unlink $tmp;
        return (1, $c);
    }
    return (0, $r->{content} // "HTTP $r->{status}");
}

# (ok) -- download to a file (GitHub binaries)
sub cstools_https_save {
    my ($url, $path, $timeout) = @_;
    $timeout ||= 180;
    my $u = HTTP::Tiny->new(timeout => $timeout, verify_SSL => 1);
    my $r = $u->get($url, { headers => { 'User-Agent' => 'cs-tools' } });
    if (!$r->{success}) {
        $u = HTTP::Tiny->new(timeout => $timeout, verify_SSL => 0);
        $r = $u->get($url, { headers => { 'User-Agent' => 'cs-tools' } });
    }
    if ($r->{success}) {
        if (open(my $fh, '>:raw', $path)) { print $fh $r->{content}; close $fh; return 1; }
        return 0;
    }
    # system downloader fallback
    if ($^O =~ /MSWin/i) {
        my $r1 = system("powershell -NoProfile -Command \"\$ProgressPreference='SilentlyContinue'; try { Invoke-WebRequest -Uri '$url' -OutFile '$path' -UseBasicParsing -TimeoutSec $timeout } catch { exit 1 }\"");
        return $r1 == 0;
    }
    my $ok = system("curl -sSL --max-time $timeout -o \"$path\" \"$url\"") == 0;
    $ok = (system("wget -q -T $timeout -O \"$path\" \"$url\"") == 0) unless $ok;
    return $ok;
}

################  GitHub latest release -> (tag, { asset => url }) or undef
sub cstools_release {
    my ($repo) = @_;
    my $api = "https://api.github.com/repos/$repo/releases/latest";
    my ($ok, $content) = cstools_https_get($api, 30);
    return undef unless $ok;
    my $data;
    eval { $data = decode_json($content) };
    return undef unless $data && ref $data eq 'HASH' && $data->{tag_name};
    my %asset;
    for my $a (@{$data->{assets} // []}) {
        next unless $a->{name} && $a->{browser_download_url};
        $asset{$a->{name}} = $a->{browser_download_url};
    }
    return ($data->{tag_name}, \%asset);
}

################  newest version with a 1h cache (_cfg/cstools_versions) --
# the menu lists 6 tools, each would cost a GitHub API call per load;
# cache avoids exhausting the unauthenticated rate limit (60/h).
sub cstools_latest_tag {
    my ($repo, $force) = @_;
    my $w = (defined $wpath && $wpath ne '') ? $wpath : '/opt/csweb-gui';
    make_path("$w/_cfg") unless -d "$w/_cfg";
    my $cachef = "$w/_cfg/cstools_versions";
    my %cache;
    if (open(my $fh, '<', $cachef)) {
        while (my $l = <$fh>) {
            chomp $l;
            $l =~ s/^\x{FEFF}//;   # strip UTF-8 BOM (user-edited files)
            next if $l =~ /^\s*#/;
            if ($l =~ /^(\S+)\s*=\s*(\S+)\s*$/) { $cache{$1} = $2; }
        }
        close $fh;
    }
    my $ts = $cache{"$repo.ts"} // 0;
    if (!$force && $ts && (time() - $ts) < 3600) {
        return $cache{$repo} // '';
    }
    my ($tag) = cstools_release($repo);
    if ($tag) {
        $cache{$repo}     = $tag;
        $cache{"$repo.ts"} = time();
        if (open(my $fh, '>', $cachef)) {
            for my $k (sort keys %cache) { print $fh "$k=$cache{$k}\n"; }
            close $fh;
            chmod(0600, $cachef) unless $^O =~ /MSWin/i;
        }
        return $tag;
    }
    return $cache{$repo} // '';   # fall back to the stale cache entry
}

################  installed state -> (present, version, bin_path)
sub cstools_installed {
    my ($key) = @_;
    my $e = cstools_entry($key);
    return (0, '', '') unless $e;
    my $w = (defined $wpath && $wpath ne '') ? $wpath : '/opt/csweb-gui';
    my ($platform, $arch, $ext) = cstools_platform();
    my $osbin = "$w/data/cs_server/tools/$e->{subdir}/$platform.$arch/$e->{asset}$ext";
    my $flat   = "$w/data/cs_server/tools/$e->{asset}$ext";
    my $bin = (-f $osbin) ? $osbin : ((-f $flat) ? $flat : $osbin);
    return (0, '', $bin) unless -f $bin;
    my $ver = `"$bin" version 2>&1`;
    $ver =~ s/^\s+|\s+$//g;
    $ver = '?' if $ver eq '' || $ver =~ /error|usage/i;
    return (1, $ver, $bin);
}

################  download + install newest (keeps OS structure)
# Returns (ok, message). $dl_module = 1 also refreshes the Perl module files
# (aihelp only).
sub cstools_download {
    my ($key, $dl_module) = @_;
    my $e = cstools_entry($key);
    return (0, "Unbekanntes Tool: $key") unless $e;
    my $w = (defined $wpath && $wpath ne '') ? $wpath : '/opt/csweb-gui';
    my $tw = (defined $tpath && $tpath ne '') ? $tpath : "$w/tmp";
    make_path($tw);

    my ($tag, $assets) = cstools_release($e->{repo});
    return (0, "GitHub release nicht erreichbar (" . $e->{repo} . ").") unless $tag;
    my ($platform, $arch, $ext) = cstools_platform();
    my $asset_platform = cstools_asset_platform($e, $platform);
    return (0, "Kein Release-Asset fuer $platform/$arch ($tag) -- " . $e->{name} . " unterstuetzt dieses OS nicht.") if $asset_platform eq '';
    my $asset_name = ($e->{kind} eq 'raw')
        ? "$e->{asset}-$asset_platform-$arch$ext"        # cs-stream-windows-amd64.exe
        : "$e->{asset}-$asset_platform.$arch.tar.gz";    # cs-aihelp-mswin.amd64.tar.gz
    my $url = $assets->{$asset_name};
    return (0, "Kein Release-Asset ($asset_name) fuer $platform/$arch ($tag).") unless $url;

    my $u = undef;   # cstools_https_* handles the client internally
    my $dl = sub {
        my ($url2) = @_;
        return cstools_https_save($url2, "$tw/cstool_dl.tmp", 180) ? 1 : 0;
    };
    my $dok = $dl->($url);
    return (0, 'Download fehlgeschlagen.') unless $dok;
    my $dst = "$tw/$asset_name";
    if (!rename("$tw/cstool_dl.tmp", $dst) && !(-f $dst)) {
        copy("$tw/cstool_dl.tmp", $dst) or return (0, "Kann $dst nicht schreiben.");
        unlink "$tw/cstool_dl.tmp";
    }

    # install keeping the OS structure: tools/<tool>/<platform>.<arch>/<tool>[.exe]
    my $osdir = "$w/data/cs_server/tools/$e->{subdir}/$platform.$arch";
    make_path($osdir);
    my $target = "$osdir/$e->{asset}$ext";

    if ($e->{kind} eq 'raw') {
        # the downloaded file IS the binary
        copy($dst, $target) or return (0, "Kopieren nach $target fehlgeschlagen.");
        unlink $dst;
    } else {
        # tar archive: extract + copy the inner binary
        my $exdir = "$tw/cstool_$key";
        remove_tree($exdir) if -d $exdir;
        make_path($exdir);
        my $okx = (system("tar -xzf \"$dst\" -C \"$exdir\" 2>NUL") == 0);
        if (!$okx) { $okx = (system("gzip -dc \"$dst\" 2>NUL | tar -xf - -C \"$exdir\"") == 0); }
        unlink $dst;
        if (!$okx) { remove_tree($exdir); return (0, 'Archiv-Extraktion fehlgeschlagen.'); }
        my $bin = '';
        if (-f "$exdir/$e->{asset}$ext") { $bin = "$exdir/$e->{asset}$ext"; }
        elsif (opendir(my $dh, $exdir)) {
            while (my $d = readdir $dh) {
                next if $d =~ /^\./;
                next unless -d "$exdir/$d";
                if (-f "$exdir/$d/$e->{asset}$ext") { $bin = "$exdir/$d/$e->{asset}$ext"; last; }
            }
            closedir $dh;
        }
        if ($bin eq '') { remove_tree($exdir); return (0, 'Binary im Archiv nicht gefunden.'); }
        copy($bin, $target) or do { remove_tree($exdir); return (0, "Kopieren nach $target fehlgeschlagen."); };
        remove_tree($exdir);
    }
    chmod(0755, $target) unless $^O =~ /MSWin/i;
    # refresh the latest-version cache for this repo
    cstools_latest_tag($e->{repo}, 1);

    my $msg = "$e->{name} installiert ($tag, $platform/$arch).";
    if ($dl_module && $e->{module}) {
        my $version = $tag; $version =~ s/^v//;
        my $murl = $assets->{"$e->{asset}-$version.tar.gz"} // $assets->{"$e->{asset}-$tag.tar.gz"};
        if ($murl) {
            my $mok = $dl->($murl);
            if ($mok) {
                my $mdst = "$tw/cstool_mod.tar.gz";
                if (rename("$tw/cstool_dl.tmp", $mdst) || copy("$tw/cstool_dl.tmp", $mdst)) {
                    unlink "$tw/cstool_dl.tmp";
                }
                my $mex = "$tw/cstool_mod";
                remove_tree($mex) if -d $mex;
                make_path($mex);
                my $okm = (system("tar -xzf \"$mdst\" -C \"$mex\" 2>NUL") == 0);
                if (!$okm) { $okm = (system("gzip -dc \"$mdst\" 2>NUL | tar -xf - -C \"$mex\"") == 0); }
                unlink $mdst;
                if ($okm) {
                    my $modroot = -d "$mex/cs-aihelp" ? "$mex/cs-aihelp" : $mex;
                    my @files = (
                        'data/menues/_lib/windows/aihelplib.pl',
                        'data/wwwroot/cgi-bin/cs-aihelp.pl',
                        'data/wwwroot/cgi-bin/cs-aihelp-exec.pl',
                        'data/menues/10_System/05_Services/12_AI_Helpdesk/action.pl',
                        'data/menues/05_Help/00_AI_Helpdesk/action.pl',
                        'data/howto.ai/ai-helpdesk.info',
                    );
                    my $n = 0;
                    for my $rel (@files) {
                        next unless -f "$modroot/$rel";
                        my $dstrel = "$w/$rel";
                        my ($dir) = $dstrel =~ m{(.*)/[^/]+$};
                        make_path($dir) unless -d $dir;
                        if (copy("$modroot/$rel", $dstrel)) { $n++; }
                    }
                    $msg .= " Module aktualisiert ($n Dateien).";
                }
                remove_tree($mex);
            }
        }
    }
    return (1, $msg);
}

1;

