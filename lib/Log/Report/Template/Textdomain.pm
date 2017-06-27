use warnings;
use strict;

package Log::Report::Template::Textdomain;
use base 'Log::Report::Domain';

use Log::Report 'log-report-template';

use Log::Report::Message ();

=chapter NAME

Log::Report::Template::Textdomain - template translation with one domain

=chapter SYNOPSIS

 my $templater = Log::Report::Template->new(...);
 my $domain    = $templater->newTextdomain(%options);

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

=cut

sub init($)
{   my ($self, $args) = @_;
    $self->SUPER::init($args);

	if(my $only =  $args->{only_in_directory})
    {   my @only = ref $only eq 'ARRAY' ? @$only : $only;
		my $dirs = join '|', map "\Q$_\E", @only;
        $self->{LRTT_only_in} = qr!^(?:$dirs)(?:$|/)!;
    }

	$self->{LRTT_function} = $args->{translation_function} || 'loc';
	my $lexicon = $self->{LRTT_lexicon}  = $args->{lexicon};
    $self;
}

#----------------
=section Accessors

=method function
Returns the name of the function which is used for translations.
=cut

sub function() { shift->{LRTT_function} }

=method lexicon
Directory where the translation tables are kept.
=cut

sub lexicon() { shift->{LRTT_lexicon} }

=method expectedIn $filename
Return true when the function name which relates to this domain is
allowed to be used for the indicated file.  The msgid extractor will warn
when there is no match.
=cut

sub expectedIn($)
{   my ($self, $fn) = @_;
    my $only = $self->{LRTT_only_in} or return 1;
    $fn =~ $only;
}

#----------------
=section Translating

=method translationFunction

This method returns a CODE which is able to handle a call for
translation by Template Toolkit.

=cut

sub translationFunction($)
{	my ($self, $service) = @_;
my $lang = 'NL';

    # Prepare as much and fast as possible, because it gets called often!
    sub { # called with ($msgid, \%params)
        $_[1]->{_stash} = $service->{CONTEXT}{STASH};
        Log::Report::Message->fromTemplateToolkit($self, @_)->toString($lang);
    };
}

sub translationFilter()
{	my $self   = shift;
	my $domain = $self->name;
my $lang = 'NL';

    # Prepare as much and fast as possible, because it gets called often!
    # A TT filter can be either static or dynamic.  Dynamic filters need to
    # implement a "a factory for static filters": a sub which produces a
    # sub which does the real work.
    sub {
        my $context = shift;
		my $pairs   = pop if @_ && ref $_[-1] eq 'HASH';
        sub { # called with $msgid (template container content) only, the
              # parameters are caught when the factory produces this sub.
             $pairs->{_stash} = $context->{STASH};
             Log::Report::Message->fromTemplateToolkit($self, $_[0], $pairs)
                ->toString($lang);
        }
    };
}

sub _reportMissingKey($$)
{   my ($self, $sp, $key, $args) = @_;

    # Try to grab the value from the stash.  That's a major advantange
    # of TT over plain Perl: we have access to the variable namespace.

    my $stash = $args->{_stash};
	if($stash)
    {   my $value = $stash->get($key);
        return $value if defined $value && length $value;
    }

    warning
      __x"Missing key '{key}' in format '{format}', in {use //template}"
      , key => $key, format => $args->{_format}
      , use => $stash->{template}{name};

    undef;
}

1;
