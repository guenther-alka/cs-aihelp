#!
use strict;

################
# AI Helpdesk -- chat (Help > AI Helpdesk)
# (c) napp-it.org 2026
#
# Full chat page: history list (resume), quick questions, copy button,
# elapsed-time indicator, new-conversation button. The floating popup is
# also demonstrated on this page (see aihelplib.pl ai_popup).
#
# Communication: browser JS -> fetch() POST /cgi-bin/cs-aihelp.pl (JSON) ->
# aihelplib.pl provider call -> answer rendered in the chat div, no reload.
# See data/howto.ai/ai-helpdesk.info.

sub my_action {

    my ($out, $var);

    eval { &mylib_menue_system };
    &load_lib('aihelplib.pl');
    print "<script language='javascript'>\$('#hl').html('AI helpdesk for $in{'member'}\:$current{'on'}')</script>\n";

    ai_chat_page($in{'member'}, $in{'l1'}, $in{'l2'}, $in{'l3'});

    &log_end;
} #/ my_action

1;
