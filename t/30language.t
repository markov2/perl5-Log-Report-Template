#!/usr/bin/env perl
# Test translation language selection
use warnings;
use strict;

use Test::More;
use Log::Report mode => 'DEBUG';

use_ok 'Log::Report::Template';
use_ok 'Log::Report::Translator::POT';

my $templater = Log::Report::Template->new;
isa_ok $templater, 'Log::Report::Template';

(my $lexicon) = grep -d, 't/30lexicon', '30lexicon';
defined $lexicon or die "Cannot find lexicon";

my $translator = Log::Report::Translator::POT->new(lexicons => $lexicon);
is $translator->translate((__x"language", _domain => 'test'), 'en_GB.utf-8'), 'Brittisch English';

my $domain = $templater->addTextdomain(name => 'test');
$domain->configure(
   translator => $translator,
);

### no translation

my $output = '';
$templater->process(\'[% loc("language") %]', { }, \$output)
    or $templater->error;

is $output, "language", 'default language';

### translate to English

$output = '';
$templater->translateTo('en_GB.utf-8');

$templater->process(\'[% loc("language") %]', { }, \$output)
    or $templater->error;

is $output, "Brittisch English", 'English';

done_testing;
