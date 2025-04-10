# This code is part of distribution Log-Report-Template. Meta-POD processed
# with OODoc into POD and HTML manual-pages.  See README.md
# Copyright Mark Overmeer.  Licensed under the same terms as Perl itself.

#!!! This code is  of
# to use Log::Report::Template instead of (Template Toolkit's) Template module.
# Follow issue https://github.com/PerlDancer/Dancer2/issues/1722 to see whether
# this module can be removd.

package Dancer2::Template::TTLogReport;

#XXX rework of Dancer2::Template::TemplateToolkit 1.1.2

use Moo;
use Dancer2::Core::Types;
use Dancer2::FileUtils qw<path>;
use Scalar::Util qw<weaken>;
use Log::Report::Template ();

with 'Dancer2::Core::Role::Template';

=encoding UTF-8

=chapter NAME

Dancer2::Template::TTLogReport - Template toolkit engine with Log::Report translations for Dancer2

=chapter SYNOPSIS

To use this engine, you may configure L<Dancer2> via C<config.yaml>:

 template:   "TTLogReport"

Or you may also change the rendering engine on a per-route basis by
setting it manually with C<set>:

  set template => 'TTLogReport';

Application:

  # In your daemon startup
  my $pot    = Log::Report::Translator::POT->new(lexicon => $poddir);
  my $domain = (engine 'template')->addTextdomain(name => $mydomain);
  $domain->configure(translator => $pot);

  # Use it:
  get '/' => sub {
    template index => {
        title        => 'my webpage',

        # The actual language is stored in the user session.
        translate_to => 'nl_NL.utf-8',
    };
  };

=chapter DESCRIPTION

This template engine allows you to use L<Template>::Toolkit in L<Dancer2>,
including the translation extensions offered by L<Log::Report::Template>.

=chapter METHODS

=section Constructors
Standard M<Moo> with M<Dancer2::Core::Role::Template> extensions.
=cut

sub _build_engine { $_[0]->tt; $_[0] }

=section Accessors

=method tt
Returns the M<Log::Report::Template> object which is performing the
template processing.  This object gets instantiated based on values
found in the Dancer2 configuration file.
=cut

has tt => ( is => 'rw', isa => InstanceOf ['Template'], builder => 1 );

sub _build_tt {
	my $self	  = shift;
	my %config	  = %{$self->config};
	my $charset   = $self->charset;
	my $templater = delete $config{templater}  || 'Log::Report::Template';

	$Template::Stash::PRIVATE = undef if delete $config{show_private_variables};

	weaken(my $ttt = $self);
	my $include_path = delete $config{include_path};

	$templater->new(
		ANYCASE   => 1,
		ABSOLUTE  => 1,
		START_TAG => delete $config{start_tag} || '\[\%',
		END_TAG   => delete $config{end_tag}   || delete $config{stop_tag} || '\%\]',
		INCLUDE_PATH => [ (defined $include_path ? $include_path : ()), sub { [ $ttt->views ] } ],
		(length $charset) ? (ENCODING => $charset) : (),
		%config,
	);
}

#-----------
=section Action

=method addTextDomain %options
Forwards the C<%options> to M<Log::Report::Template::addTextdomain()>.

=example
  my $lexicon = $directory;  # f.i. $directory/<domain>/nl_NL.utf-8.po
  my $tables  = Log::Report::Translator::POT->new(lexicon => $lexicon);
  (engine 'template')->addTextdomain(name => 'mydomain')->configure(translator => $tables);
=cut

sub addTextdomain(%) {
	my $self = shift;
	$self->tt->addTextdomain(@_);
}

=method render $template, \%tokens

Renders the template.  The first arg is a filename for the template file
or a reference to a string that contains the template. The second arg
is a hashref for the tokens that you wish to pass to
L<Template::Toolkit> for rendering.

sub render($$) {
	my ($self, $template, $tokens) = @_;
	my $content = '';
	my $charset = $self->charset;
	my @options = (length $charset) ? (binmode => ":encoding($charset)") : ();

	if(my $lang = $tokens->{translate_to}) {
		$self->tt->translateTo($lang);
	}

	$self->tt->process($template, $tokens, \$content, @options)
		or $self->log_cb->(core => 'Failed to render template: ' . $self->tt->error);

	$content;
}

#### The next is reworked from Dancer2::Template::TemplateToolkit.  No idea
#### whether it is reasonable.

# Override *_pathname methods from Dancer2::Core::Role::Template
# Let TT2 do the concatenation of paths to template names.
#
# TT2 will look in a its INCLUDE_PATH for templates.
# Typically $self->views is an absolute path, and we set ABSOLUTE => 1 above.
# In that case TT2 does NOT iterate through what is set for INCLUDE_PATH
# However, if its not absolute, we want to allow TT2 iterate through the
# its INCLUDE_PATH, which we set to be $self->views.

sub view_pathname($) {
	my ($self, $view) = @_;
	$self->_template_name($view);
}

sub layout_pathname($) {
	my ($self, $layout) = @_;
	path($self->layout_dir, $self->_template_name($layout));
}

sub pathname_exists($) {
	my ($self, $pathname) = @_;

	# dies if pathname can not be found via TT2's INCLUDE_PATH search
	my $exists = eval { $self->engine->service->context->template($pathname); 1 };
	$exists or $self->log_cb->(debug => $@);

	$exists;
}

1;

__END__

=chapter DETAILS

=section Dancer2 Configuration

Most configuration variables are available when creating a new instance
of a L<Template>::Toolkit object can be declared in your config.yml file.
For example:

  template: TTLogReport

  engines:
    template:
      TTLogReport:
        start_tag: '<%'
        end_tag:   '%>'

(Note: C<start_tag> and C<end_tag> are regexes.  If you want to use PHP-style
tags, you will need to list them as C<< <\? >> and C<< \?> >>.)
See L<Template::Manual::Config> for the configuration variables.

In addition to the standard configuration variables, the option C<show_private_variables>
is also available. Template::Toolkit, by default, does not render private variables
(the ones starting with an underscore). If in your project it gets easier to disable
this feature than changing variable names, add this option to your configuration.

  show_private_variables: true

B<Warning:> Given the way Template::Toolkit implements this option, different Dancer2
applications running within the same interpreter will share this option!

=section Advanced Customization

Module L<Dancer2::Template::TemplateToolkit> describes how to extend the Template
by wrapping the C<_build_engine> method.  The instantiation trick is insufficient
for a bit more complex modules, like our Log::Report translation feature.  You may
be able to extend this module with your own templater, however.

    # in config.yml
    engines:
      template:
        TTLogReport:
          start_tag: '<%'
          end_tag:   '%>'
          templater: Log::Report::Template  # default

=cut

