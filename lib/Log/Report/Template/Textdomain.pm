# This code is part of distribution Log-Report-Template. Meta-POD processed
# with OODoc into POD and HTML manual-pages.  See README.md
# Copyright Mark Overmeer.  Licensed under the same terms as Perl itself.

package Log::Report::Template::Textdomain;
use base 'Log::Report::Domain';

use warnings;
use strict;

use Log::Report 'log-report-template';

use Log::Report::Message ();
use Scalar::Util qw(weaken);

=chapter NAME

Log::Report::Template::Textdomain - template translation with one domain

=chapter SYNOPSIS

 my $templater = Log::Report::Template->new(...);
 my $domain    = $templater->addTextdomain(%options);

=chapter DESCRIPTION
Manage one translation domain for M<Log::Report::Template>.

=chapter METHODS

=section Constructors

=c_method new %options

=option  only_in_directory DIRECTORY|ARRAY
=default only_in_directory C<undef>
The textdomain can only be used in the indicated directories: if found
anywhere else, it's an error.  When not specified, the function is
allowed everywhere.

=option  translation_function STRING
=default translation_function 'loc'
The name of the function as used in the template to call for translation.
See M<function()>.  It must be unique over all text-domains used.

=option  lexicon DIRECTORY
=default lexicon C<undef>

=requires templater M<Log::Report::Template>-object

=option  lang LANGUAGES
=default lang C<undef>
[1.01] Initial language to translate to.  Usually, this language which change
for each user connection via M<translateTo()>.
=cut

sub init($)
{	my ($self, $args) = @_;
	$self->SUPER::init($args)->_initMe($args);
}

sub _initMe($)
{	my ($self, $args) = @_;

	if(my $only =  $args->{only_in_directory})
	{	my @only = ref $only eq 'ARRAY' ? @$only : $only;
		my $dirs = join '|', map "\Q$_\E", @only;
		$self->{LRTT_only_in} = qr!^(?:$dirs)(?:$|/)!;
	}

	$self->{LRTT_function} = $args->{translation_function} || 'loc';
	$self->{LRTT_lexicon}  = $args->{lexicon};
	$self->{LRTT_lang}     = $args->{lang};

	$self->{LRTT_templ}    = $args->{templater} or panic "Requires templater";
	weaken $self->{LRTT_templ};

	$self;
}

=c_method upgrade $domain, %options
Upgrade a base class M<Log::Report::Domain>-object into an Template
domain.

This is a bit akward process, needed when one of the code packages
uses the same domain as the templating system uses.  The generic domain
configuration stays intact.
=cut

sub upgrade($%)
{	my ($class, $domain, %args) = @_;

	ref $domain eq 'Log::Report::Domain'
		or error __x"extension to domain '{name}' already exists", name => $domain->name;

	(bless $domain, $class)->_initMe(\%args);
}

#----------------
=section Attributes

=method templater
The M<Log::Report::Template> object which is using this textdomain.
=cut

sub templater() { $_[0]->{LRTT_templ} }

=method function
Returns the name of the function which is used for translations.
=cut

sub function() { $_[0]->{LRTT_function} }

=method lexicon
Directory where the translation tables are kept.
=cut

sub lexicon() { $_[0]->{LRTT_lexicon} }

=method expectedIn $filename
Return true when the function name which relates to this domain is
allowed to be used for the indicated file.  The msgid extractor will warn
when there is no match.
=cut

sub expectedIn($)
{	my ($self, $fn) = @_;
	my $only = $self->{LRTT_only_in} or return 1;
	$fn =~ $only;
}

=method lang
The language we are going to translate to.  Change this with M<translateTo()>
for this domain, or better M<Log::Report::Template::translateTo()>.
=cut

sub lang() { $_[0]->{LRTT_lang} }

#----------------
=section Translating

=method translateTo $lang
Set the language to translate to for C<$lang>, for this domain only.  This may
be useful when various text domains do not support the same destination languages.
But in general, you can best use M<Log::Report::Template::translateTo()>.
=cut

sub translateTo($)
{	my ($self, $lang) = @_;
	$self->{LRTT_lang} = $lang;
}

=method translationFunction
This method returns a CODE which is able to handle a call for
translation by Template Toolkit.
=cut

sub translationFunction($)
{	my ($self, $service) = @_;

	# Prepare as much and fast as possible, because it gets called often!
	sub { # called with ($msgid, @positionals, [\%params])
		my $msgid  = shift;
		my $params  = @_ && ref $_[-1] eq 'HASH' ? pop @_ : {};
		if($msgid =~ m/\|/ && ! defined $params->{_count})
		{	@_ or error __x"no counting positional for '{msgid}'", msgid => $msgid;
			$params->{_count} = shift;
		}
		@_ and error __x"superfluous positional parameters for '{msgid}'", msgid => $msgid;
		$params->{_stash} = $service->{CONTEXT}{STASH};
		Log::Report::Message->fromTemplateToolkit($self, $msgid, $params)->toString($self->lang);
	};
}

sub translationFilter()
{	my $self   = shift;
	my $domain = $self->name;

	# Prepare as much and fast as possible, because it gets called often!
	# A TT filter can be either static or dynamic.  Dynamic filters need to
	# implement a "a factory for static filters": a sub which produces a
	# sub which does the real work.
	sub {
		my $context = shift;
		my $params  = @_ && ref $_[-1] eq 'HASH' ? pop @_ : {};
		$params->{_count} = shift if @_;
		$params->{_error} = 'too many' if @_;   # don't know msgid yet

		sub { # called with $msgid (template container content) only, the
			  # parameters are caught when the factory produces this sub.
			my $msgid = shift;
			! defined $params->{_count} || $msgid =~ m/\|/
				or error __x"message does not contain counting alternatives in '{msgid}'", msgid => $msgid;

			$msgid !~ m/\|/ || defined $params->{_count}
				or error __x"no counting positional for '{msgid}'", msgid => $msgid;

			! $params->{_error}
				or error __x"superfluous positional parameters for '{msgid}'", msgid => $msgid;
			$params->{_stash}  = $context->{STASH};
			Log::Report::Message->fromTemplateToolkit($self, $msgid, $params)->toString($self->lang);
		}
	};
}

sub _reportMissingKey($$)
{	my ($self, $sp, $key, $args) = @_;

	# Try to grab the value from the stash.  That's a major advantange
	# of TT over plain Perl: we have access to the variable namespace.

	my $stash = $args->{_stash};
	if($stash)
	{	my $value = $stash->get($key);
		return $value if defined $value && length $value;
	}

	warning __x"Missing key '{key}' in format '{format}', in {use //template}",
		key => $key, format => $args->{_format},
		use => $stash->{template}{name};

	undef;
}

1;
