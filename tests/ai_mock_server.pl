# ai_mock_server.pl -- minimal one-shot HTTP server for testing the
# OpenAI-compatible provider call path (returns a fixed JSON chat response).
use strict;
use IO::Socket::INET;

my $port = shift || 19091;
my $sock = IO::Socket::INET->new(LocalAddr=>'127.0.0.1', LocalPort=>$port,
    Proto=>'tcp', Listen=>50, ReuseAddr=>1) or die "cannot listen: $!";
$|=1;
while (1) {
    my $c = $sock->accept() or next;
    my $req = '';
    while (1) {
        my $buf = '';
        my $n = sysread($c, $buf, 8192);
        last unless $n;
        $req .= $buf;
        last if $req =~ /\r\n\r\n/;
    }
    # consume the request body if Content-Length is present
    if ($req =~ /Content-Length:\s*(\d+)/i) {
        my $len = $1;
        my $hdr_end = index($req, "\r\n\r\n") + 4;
        while (length($req) < $len + $hdr_end) {
            my $buf=''; my $n=sysread($c,$buf,8192); last unless $n; $req.=$buf;
        }
    }
    my $resp;
    my ($head, $body) = split(/\r\n\r\n/, $req, 2);
    my ($reqline) = split(/\r\n/, $head);
    my $wants_action = ($body // '') =~ /ACTIONTEST/ ? 1 : 0;
    if ($reqline =~ m{GET (\S+)}) {
        if ($1 =~ m{/api/tags}) {
            $resp = '{"models":[{"name":"mock-llm:latest"},{"name":"mock-llm2:latest"}]}';
        } elsif ($1 =~ m{/cse}) {
            $resp = '{"items":[{"title":"CSE Title One","link":"https://cse.example.com/one","snippet":"CSE snippet one"},'
                  . '{"title":"CSE Title Two","link":"https://cse.example.com/two","snippet":"CSE snippet two"}]}';
        } elsif ($1 =~ m{/lite}) {
            $resp = '<html><body><table border="0">'
                . '<tr><td>1.</td><td><a rel="nofollow" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fmock.example.com%2Fzfs-snap&amp;rut=abc" class=\'result-link\'>ZFS Snapshots Guide</a></td></tr>'
                . '<tr><td>&nbsp;</td><td class=\'result-snippet\'>How to create a <b>ZFS</b> snapshot with the zfs snapshot command.</td></tr>'
                . '<tr><td>2.</td><td><a rel="nofollow" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fmock.example.com%2Fsnap2&amp;rut=def" class=\'result-link\'>Second Result</a></td></tr>'
                . '</table></body></html>';
        } else {
            $resp = '{"choices":[{"message":{"content":"MOCK-ANTWORT aus dem Testserver"}}],"model":"mock"}';
        }
    } elsif ($reqline =~ m{/api/chat}) {
        if ($wants_action) {
            # Level 2: answer with a proposed command block
            $resp = '{"message":{"content":"Ich mache einen Snapshot.\\n[[ACTION]]{\"cmd\":\"zfs snapshot tank/data@auto\",\"reason\":\"mock action test\"}[[/ACTION]]"},"model":"mock"}';
        } else {
            $resp = '{"message":{"content":"MOCK-OLLAMA-ANTWORT"},"model":"mock"}';
        }
    } else {
        $resp = '{"choices":[{"message":{"content":"MOCK-ANTWORT aus dem Testserver"}}],"model":"mock"}';
    }
    print $c "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n"
        . "Content-Length: " . length($resp) . "\r\nConnection: close\r\n\r\n$resp";
    close $c;
}
