# This code is part of distribution Log-Report-Template. Meta-POD processed
# with OODoc into POD and HTML manual-pages.  See README.md
# Copyright Mark Overmeer.  Licensed under the same terms as Perl itself.

package Log::Report::Template;
use base 'Template';

use warnings;
use strict;

use Log::Report 'log-report-template';
use Log::Report::Template::Textdomain ();
# use Log::Report::Template::Extract on demand.

use File::Find        qw(find);
use Scalar::Util      qw(blessed);
use Template::Filters ();
use String::Print     ();

=encoding utf-8

=chapter NAME

Log::Report::Template - Template Toolkit with translations

=chapter SYNOPSIS

  use Log::Report::Template;
  my $templater = Log::Report::Template->new(%config);
  $templater->addTextdomain(name => "Tic", lexicons => ...);
  $templater->process('template_file.tt', \%vars);

=chapter DESCRIPTION

This module extends M<Template>, which is the core of Template Toolkit.
The main addition is support for translations via the translation
framework offered by M<Log::Report>.

You add translations to a template system, by adding calls to some
translation function (by default called C<loc()>) to your template text.
That function will perform dark magic to collect the translation from
translation tables, and fill in values.  For instance:

  <div>Price: [% price %]</div>          # no translation
  <div>[% loc("Price: {price}") %]</div> # translation optional

It's quite a lot of work to make your templates translatable.
Please read the L</DETAILS> section before you start using this module.

=chapter METHODS

=section Constructors

=c_method new %options
Create a new translator object.  You may pass the C<%options> as HASH or
PAIRS.  By convension, all basic Template Toolkit options are in capitals.
Read M<Template::Config> about what they mean.  Extension options provided
by this module are all in lower-case.

In a web-environment, you want to start this before your webserver starts
forking.

=option  processing_errors 'NATIVE'|'EXCEPTION'
=default processing_errors 'NATIVE'
The Template Toolkit infrastructure handles errors carefully: C<undef> is
returned and you need to call M<error()> to collect it.

=option  template_syntax 'UNKNOWN'|'HTML'
=default template_syntax 'HTML'
Linked to M<String::Print::new(encode_for)>: the output of the translation
is HTML encoded unless the inserted value name ends on C<_html>.
Read L</"Translation into HTML">

=option  modifiers ARRAY
=default modifiers []
Add a list of modifiers to the default set.  Modifiers are part of the
formatting process, when values get inserted in the translated string.
Read L</"Formatter value modifiers">.

=option  translate_to LANGUAGE
=default translate_to C<undef>
Globally set the output language of template processing.  Usually, this
is derived from the logged-in user setting or browser setting.
See M<translateTo()>.

=option  textdomain_class CLASS
=default textdomain_class C<Log::Report::Template::Textdomain>
Use your own extension to M<Log::Report::Template::Textdomain>.
=cut

sub new
{	my $class = shift;

	# Template::Base gladly also calls _init() !!
	my $self = $class->SUPER::new(@_) or panic $class->error;
	$self;
}

sub _init($)
{	my ($self, $args) = @_;

	if(ref $self eq __PACKAGE__)
	{	# Instantiated directly
		$self->SUPER::_init($args);
	}
	else
	{	# Upgrade from existing Template object
		bless $self, __PACKAGE__;
	}

	my $delim = $self->{LRT_delim} = $args->{DELIMITER} || ':';
	my $incl = $args->{INCLUDE_PATH} || [];
	$self->{LRT_path} = ref $incl eq 'ARRAY' ? $incl : [ split $delim, $incl ];

	my $handle_errors = $args->{processing_errors} || 'NATIVE';
	if($handle_errors eq 'EXCEPTION') { $self->{LRT_exceptions} = 1 }
	elsif($handle_errors ne 'NATIVE')
	{	error __x"illegal value '{value}' for 'processing_errors' option",
			value => $handle_errors;
	}

	$self->{LRT_formatter} = $self->_createFormatter($args);
	$self->{LRT_trTo} = $args->{translate_to};
	$self->{LRT_tdc}  = $args->{textdomain_class} || 'Log::Report::Template::Textdomain';
	$self->_defaultFilters;
	$self;
}

sub _createFormatter($)
{	my ($self, $args) = @_;
	my $formatter = $args->{formatter};
	return $formatter if ref $formatter eq 'CODE';

	my $syntax = $args->{template_syntax} || 'HTML';
	my $modifiers = $self->_collectModifiers($args);

	my $sp     = String::Print->new(
		encode_for => ($syntax eq 'HTML' ? $syntax : undef),
		modifiers  => $modifiers,
	);

	sub { $sp->sprinti(@_) };
}

#---------------
=section Attributes

=method formatter
Get the C<String::Print> object which formats the messages.
=cut

sub formatter() { $_[0]->{LRT_formatter} }

=method translateTo [$language]
=cut

sub translateTo(;$)
{	my $self = shift;
	my $old  = $self->{LRT_trTo};
	@_ or return $old;

	my $lang = shift;

	return $lang   # language unchanged?
		if ! defined $lang ? ! defined $old
		 : ! defined $old  ? 0 : $lang eq $old;

	$_->translateTo($lang) for $self->domains;
	$self->{LRT_trTo} = $lang;
}

#---------------
=section Handling text domains

=method addTextdomain %options
Create a new M<Log::Report::Template::Textdomain> object.
See its C<new()> method for the options.

Additional facts about the options: you may specify C<only_in_directory>
as a path. Those directories must be in the INCLUDE_PATH as well.
The (domain) C<name> must be unique, and the C<function> not yet in use.

When the code also uses this textdomain, then that configuration will
get extended with this configuration.

=example
  my $domain = $templater->addTextdomain(
    name     => 'my-project',
    function => 'loc',   # default
  );

=cut

sub addTextdomain($%) {
	my ($self, %args) = @_;

	if(my $only = $args{only_in_directory})
	{	my $delim = $self->{LRT_delim};
		$only     = $args{only_in_directory} = [ split $delim, $only ]
			if ref $only ne 'ARRAY';

		my @incl  = $self->_incl_path;
		foreach my $dir (@$only)
		{	next if grep $_ eq $dir, @incl;
			error __x"directory {dir} not in INCLUDE_PATH, used by {option}",
				dir => $dir, option => 'addTextdomain(only_in_directory)';
		}
	}

	$args{templater} ||= $self;
	$args{lang}      ||= $self->translateTo;

	my $name    = $args{name};
	my $td_class= $self->{LRT_tdc};
	my $domain;
	if($domain  = textdomain $name, 'EXISTS')
	{	$td_class->upgrade($domain, %args);
	}
	else
	{	$domain = textdomain($td_class->new(%args));
	}

	my $func    = $domain->function;
	if((my $other) = grep $func eq $_->function, $self->domains)
	{	error __x"translation function '{func}' already in use by textdomain '{name}'", func => $func, name => $other->name;
	}
	$self->{LRT_domains}{$name} = $domain;

	# call as function or as filter
	$self->_stash->{$func}  = $domain->translationFunction($self->service);
	$self->context->define_filter($func => $domain->translationFilter, 1);
	$domain;
}

sub _incl_path() { @{shift->{LRT_path}} }
sub _stash()     { shift->service->context->stash }

=method domains
Returns a LIST with all defined textdomains, unsorted.
=cut

sub domains()   { values %{$_[0]->{LRT_domains} } }

=method domain $name
Returns the textdomain with the specified C<$name>.
=cut

sub domain($)   { $_[0]->{LRT_domains}{$_[1]} }

=method extract %options
Extract message ids from the templates, and register them to the lexicon.
Read section L</"Extracting PO-files"> how to use this method.

Show statistics will be show when the Log::Report more is VERBOSE or
DEBUG.

=option  charset CHARSET
=default charset 'UTF-8'

=option  write_tables BOOLEAN
=default write_tables <true>
When false, the po-files will not get updated.

=option  filenames FILENAME|ARRAY
=default filenames C<undef>
By default, all filenames from the INCLUDE_PATH directories which match
the C<filename_match> are processed, but you may explicitly create a
subset by hand.

=option  filename_match RegEx
=default filename_match qr/\.tt2?$/
Process all files from the INCLUDE_PATH directories which match this
regular expression.

=cut

sub extract(%)
{	my ($self, %args) = @_;

	eval "require Log::Report::Template::Extract";
	panic $@ if $@;

	my $stats   = $args{show_stats} || 0;
	my $charset = $args{charset}    || 'UTF-8';
	my $write   = exists $args{write_tables} ? $args{write_tables} : 1;

	my @filenames;
	if(my $fns  = $args{filenames} || $args{filename})
	{	push @filenames, ref $fns eq 'ARRAY' ? @$fns : $fns;
	}
	else
	{	my $match = $args{filename_match} || qr/\.tt2?$/;
		my $filter = sub {
			my $name = $File::Find::name;
			push @filenames, $name if -f $name && $name =~ $match;
		};
		foreach my $dir ($self->_incl_path)
		{	trace "scan $dir for template files";
			find { wanted => sub { $filter->($File::Find::name) }, no_chdir => 1}, $dir;
		}
	}

	foreach my $domain ($self->domains)
	{	my $function = $domain->function;
		my $name     = $domain->name;

		trace "extracting msgids for '$function' from domain '$name'";

		my $extr = Log::Report::Template::Extract->new(
			lexicon => $domain->lexicon,
			domain  => $name,
			pattern => "TT2-$function",
			charset => $charset,
		);

		$extr->process($_)
			for @filenames;

		$extr->showStats;
		$extr->write     if $write;
	}
}

#------------
=section Template filters

Some common activities in templates are harder when translation is
needed.  A few TT filters are provided to easy the process.

=over 4

=item Filter: cols

A typical example of an HTML component which needs translation is

  <tr><td>Price:</td><td>20 £</td></tr>

Both the price text as value need to be translated.  In plain perl
(with Log::Report) you would write

  __x"Price: {price £}", price => $product->price   # or
  __x"Price: {p.price £}", p => $product;

In HTML, there seems to be the need for two separate translations,
may in the program code.  This module (actually M<String::Print>)
can be trained to convert money during translation, because '£'
is a modifier.  The translation for Dutch (via a PO table) could be

   "Prijs: {p.price €}"

SO: we want to get both table fields in one translation.  Try this:

  <tr>[% loc("Price:\t{p.price £}" | cols %]</tr>

In the translation table, you have to place the tabs (backslash-t) as
well.

There are two main forms of C<cols>.  The first form is the containerizer:
pass 'cols' a list of container names.  The fields in the input string
(as separated by tabs) are wrapped in the named container.  The last
container name will be reused for all remaining columns.  By default,
everything is wrapped in 'td' containers.

  "a\tb\tc" | cols             <td>a</td><td>b</td><td>c</td>
  "a\tb\tc" | cols('td')       same
  "a\tb\tc" | cols('th', 'td') <th>a</th><td>b</td><td>c</td>
  "a"       | cols('div')      <div>a</div>
  loc("a")  | cols('div')      <div>xxxx</div>

The second form has one pattern, which contains (at least one) '$1'
replacement positions.  Missing columns for positional parameters
will be left blank.

  "a\tb\tc" | cols('#$3#$1#')  #c#a#
  "a"       | cols('#$3#$1#')  ##a#
  loc("a")  | cols('#$3#$1#')  #mies#aap#

=cut

sub _cols_factory(@)
{	my $self = shift;
	my $params = ref $_[-1] eq 'HASH' ? pop : undef;
	my @blocks = @_ ? @_ : 'td';
	if(@blocks==1 && $blocks[0] =~ /\$[1-9]/)
	{	my $pattern = shift @blocks;
		return sub {    # second syntax
			my @cols = split /\t/, $_[0];
			$pattern =~ s/\$([0-9]+)/$cols[$1-1] || ''/ge;
			$pattern;
		}
	}

	sub {    # first syntax
		my @cols = split /\t/, $_[0];
		my @wrap = @blocks;
		my @out;
		while(@cols)
		{	push @out, "<$wrap[0]>$cols[0]</$wrap[0]>";
			shift @cols;
			shift @wrap if @wrap > 1;
		}
		join '', @out;
	}
}

=item Filter: br

Some translations will produce more than one line of text.  Add
'<br>' after each of them.

  [% loc('intro-text') | br %]
  [% | br %][% intro_text %][% END %]
  [% FILTER br %][% intro_text %][% END %]

=cut

sub _br_factory(@)
{	my $self = shift;
	my $params = ref $_[-1] eq 'HASH' ? pop : undef;
	return sub {
		my $templ = shift or return '';
		for($templ)
		{	s/\A[\s\n]*\n//;     # leading blank lines
			s/\n[\s\n]*\n/\n/g;  # double blank links
			s/\n[\s\n]*\z/\n/;   # trailing blank lines
			s/\s*\n/<br>\n/gm;   # trailing blanks per line
		}
		$templ;
	}
}

sub _defaultFilters()
{	my $self    = shift;
	my $context = $self->context;
	$context->define_filter(cols => \&_cols_factory, 1);
	$context->define_filter(br   => \&_br_factory,   1);
	$self;
}

#------------

=back

=section Formatter value modifiers

Modifiers simplify the display of values.  Read the section about
modifiers in M<String::Print>.  Here, only some examples are shown.

You can achieve the same transformation with TT vmethods, or with the
perl code which drives your website.  The advantange is that you can
translate them.  And they are quite readible.

=over 4

=item POSIX format C<%-10s>, C<%2.4f>, etc

Exactly like format of the perl's internal C<printf()> (which is
actually being called to do the formatting)

Examples:

 # pi in two decimals
 [% loc("π = {pi %.2f}", pi => 3.14157) %]

 # show int, no fraction. filesize is a template variable
 [% loc("file size {size %d}", size => filesize + 0.5) %]


=item BYTES

Convert a file size into a nice human readible format.

Examples:

  # filesize and fn are passed as variables to the templater
  [% loc("downloaded {size BYTES} {fn}\n", size => fs, fn => fn) %]
  # may produce:   "  0 B", "25 MB", "1.5 GB", etc


=item Time-formatting YEAR, DATE, TIME, DT

Accept various time syntaxes as value, and translate them into
standard formats: year only, date in YYYY-MM-DD, time as 'HH::MM::SS',
and various DateTime formats:

Examples:

  # shows 'Copyright 2017'
  [% loc("Copyright {today YEAR}", today => '2017-06-26') %]
 
  # shows 'Created: 2017-06-26'
  [% loc("Created: {now DATE}", now => '2017-06-26 00:24:15') %]
  
  # shows 'Night: 00:24:15'
  [% loc("Night: {now TIME}", now => '2017-06-26 00:24:15') %]
  
  # shows 'Mon Jun 26 00:28:50 CEST 2017'
  [% loc("Stamp: {now DT(ASC)}", now => 1498429696) %]

=item Default //"string", //'string', or //word

When a parameter has no value or is an empty string, the word or
string will take its place.

  [% loc("visitors: {count //0}", count => 3) %]
  [% loc("published: {date DT//'not yet'}", date => '') %]
  [% loc("copyright: {year//2017 YEAR}", year => '2018') %]
  [% loc("price: {price//5 EUR}", price => product.price %]
  [% loc("price: {price EUR//unknown}", price => 3 %]

=cut

sub _collectModifiers($)
{	my ($self, $args) = @_;

	# First match will be used
	my @modifiers = @{$args->{modifiers} || []};

	# More default extensions expected here.  String::Print already
	# adds a bunch.

	\@modifiers;
}

#------------

=back

=section Template (Toolkit) base-class

The details of the following functions can be found in the M<Template>
manual page.  They are included here for reference only.

=method process $template, [\%vars, $output, \%options]

Process the C<$template> into C<$output>, filling in the C<%vars>.

=method error

If the 'processing_errors' option is 'NATIVE' (default), you have to
collect the error like this:

  $tt->process($template_fn, $vars, ...)
     or die $tt->error;

When the 'procesing_errors' option is set to 'EXCEPTION', the error is
translated into a M<Log::Report::Exception>:

  use Log::Report;
  try { $tt->process($template_fn, $vars, ...) };
  print $@->wasFatal if $@;

In the latter solution, the try() is probably only on the level of the
highest level: the request handler which catches all kinds of serious
errors at once.

=cut

{	# Log::Report exports 'error', and we use that.  Our base-class
	# 'Template' however, also has a method named error() as well.
	# Gladly, they can easily be separated.

	# no warnings 'redefined' misbehaves, at least for perl 5.16.2
	no warnings;

	sub error()
	{
		return Log::Report::error(@_)
			unless blessed $_[0] && $_[0]->isa('Template');

		return shift->SUPER::error(@_)
			unless $_[0]->{LRT_exceptions};

		@_ or panic "inexpected call to collect errors()";

		# convert Template errors into Log::Report errors
		Log::Report::error($_[1]);
	}
}


#------------
=chapter DETAILS

=section Textdomains

This module uses standard gettext PO-translation tables via the
M<Log::Report::Lexicon> distribution.  An important role here is
for the 'textdomain': the name of the set of translation tables.

For code, you say "use Log::Report '<textdomain>;" in each related
module (pm file).  We cannot do achieve comparible syntax with
Template Toolkit: you must specify the textdomain before the
templates get processed.

Your website may contain multiple separate sets of templates.  For
instance, a standard website implementation with some local extensions.
The only way to get that to work, is by using different translation
functions: one textdomain may use 'loc()', where an other uses 'L()'.

=section Supported syntax

=subsection Translation syntax

Let say that your translation function is called 'loc', which is the
default name.  Then, you can use that name as simple function.

In these examples, C<PAIRS> is a list of values to be inserted in the
C<msgid> string. When the C<msgid> is specified with a C<plural> alternative,
then a C<COUNTER> value is required to indicate which alternative is
required.

  [% loc("msgid", PAIRS) %]
  [% loc('msgid', PAIRS) %]
  [% loc("msgid|plural", COUNTER, PAIRS) %]
  [% loc("msgid|plural", _count => COUNTER, PAIRS) %]
 
  [% INCLUDE
       title = loc('something')
   %]

But also as filter.  Although filters and functions work differently
internally in Template Toolkit, it is convenient to permit both syntaxes.

  [% | loc(PAIRS) %]msgid[% END %]
  [% 'msgid' | loc(PAIRS) %]
  [% "msgid" | loc(PAIRS) %]
  
  [% "msgid|plural" | loc(COUNTER, PAIRS) %]
  [% "msgid|plural" | loc(_count => COUNTER, PAIRS) %]
  [% FILTER loc %]msgid[% END %]
  [% FILTER loc(COUNTER, PAIRS) %]msgid|plural[% END %]

As examples

  [% loc("hi {n}", n => name) %]
  [% | loc(n => name) %]hi {n}[% END %]
  [% "hi {n}" | loc(n => name) %]
  [% loc("one person|{_count} people", size) %]
  [% | loc(size) %]one person|{_count} people[% END %]
  [% 'one person|{_count} people' | loc(size) %]

These syntaxes work exacly like translations with Log::Report for your
Perl programs.  Compare this with:

  __x"hi {n}", n => name;    # equivalent to
  __x("hi {n}", n => name);  # replace __x() by loc()

=subsection Translation syntax, more magic

With TT, we can add a simplificition which we cannot offer for Perl
translations: TT variables are dynamic and stored in the stash which
we can access.  Therefore, we can lookup "accidentally" missed parameters.

  [% SET name = 'John Doe' %]
  [% loc("Hi {name}", name => name) %]  # looks silly
  [% loc("Hi {name}") %]                # uses TT stash directly


Sometimes, computation of objects is expensive: you never know.  So, you
may try to avoid repeated computation.  In the follow example, "soldOn"
is collected/computed twice:

  [% IF product.soldOn %]
  <td>[% loc("Sold on {product.soldOn DATE}")</td>
  [% END %]

The performance is predictable optimal with:

  [% sold_on = product.soldOn; IF sold_on %]
  <td>[% loc("Sold on {sold_on DATE}")</td>
  [% END %]

=subsection Translation into HTML

Usually, when data is passed from the program's internal to the template,
it should get encoded into HTML to escape some characters.  Typical TT
code:

  Title&gt; [% title | html %]

When your insert is produced by the localizer, you can do this as well
(set C<template_syntax> to 'UNKNOWN' first)

  [% loc("Title> {t}", t => title) | html %]

The default TT syntax is 'HTML', which will circumvent the need to
use the html filter.  In that default case, you only say:

  [% loc("Title> {t}", t => title) %]
  [% loc("Title> {title}") %]  # short form, see previous section

When the title is already escaped for HTML, you can circumvent that
by using tags which end on 'html':

  [% loc("Title> {t_html}", t_html => title) %]

  [% SET title_html = html(title) %]
  [% loc("Title> {title_html}") %]


=section Extracting PO-files

You may define a textdomain without doing any translations (yet)  However,
when you start translating, you will need to maintain translation tables
which are in PO-format.  PO-files can be maintained with a wide variety
of tools, for instance poedit, Pootle, virtaal, GTranslator, Lokalize,
or Webtranslateit.

=subsection Setting-up translations

Start with desiging a domain structure.  Probably, you want to create
a separate domain for the templates (external texts in many languages)
and your Perl program (internal texts with few languages).

Pick a lexicon directory, which is also inside your version control setup,
for instance your GIT repository.  Some po-editors can work together
with various version control systems.

Now, start using this module.  There are two ways: either by creating it
as object, or by extension.

  ### As object
  # Somewhere in your code
  use Log::Report::Template;
  my $templater = Log::Report::Template->new(%config);
  $templater->addTextdomain(...);

  $templater->process('template_file.tt', \%vars); # runtime
  $templater->extract(...);    # rarely, "off-line"

Some way or another, you want to be able to share the creation of the
templater and configuration of the textdomain between the run-time use
and the irregular (off-line) extraction of msgids.

The alternative is via extension:

  ### By extension
  # Somewhere in your code:
  use My::Template;
  my $templater = My::Template->new;
  $templater->process('template_file.tt', \%vars);
  
  # File lib/My/Template.pm
  package My::Template;
  use parent 'Log::Report::Template';

  sub init($) {
     my ($self, $args) = @_;
     # add %config into %$args
     $self->SUPER::init($args);
     $self->addTextdomain(...);
     $self;
  }

  1;

The second solution requires a little bit of experience with OO, but is
easier to maintain and to share.

=subsection adding a new language

The first time you run M<extract()>, you will see a file being created
in C<$lexicon/$textdomain-$charset.po>.  That file will be left empty:
copy it to start a new translation.

There are many ways to structure PO-files.  Which structure used, is
detected automatically by M<Log::Report::Lexicon>.  My personal preference 
is C<$lexicon/$textdomain/$language-$charset.po>.  On Unix-like systems,
you would do:

  # Start a new language
  mkdir mylexicon/mydomain
  cp mylexicon/mydomain-utf8.po mylexicon/mydomain/nl_NL-utf8.po 
  
  # fill the nl_NL-utf8.po file with the translation
  poedit mylexicon/mydomain/nl_NL-utf8.po
  
  # add the file to your version control system
  git add mylexicon/mydomain/nl_NL-utf8.po
  

Now, when your program sets the locale to 'nl-NL', it should start
translating to Dutch.  If it doesn't, it is not always easy to
figure-out what is wrong...

=subsection Keeping translations up to date

You have to call M<extract()> when msgids have changed or added,
to have the PO-tables updated.  The language specific tables will
get updated automatically... look for msgids which are 'fuzzy'
(need update)

You may also use the external program C<xgettext-perl>, which is
shipped with the M<Log::Report::Lexicon> distribution.

=subsection More performance via MO-files

PO-files are quite large.  You can reduce the translation table size by
creating a binary "MO"-file for each of them. M<Log::Report::Lexicon>
will prefer mo files, if it encounters them, but generation is not (yet)
organized via Log::Report components.  Search for "msgfmt" as separate
tool or CPAN module.

=cut

1;
