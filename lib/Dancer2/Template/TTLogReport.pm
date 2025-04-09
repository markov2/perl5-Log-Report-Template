# This code is part of distribution Log-Report-Template. Meta-POD processed
# with OODoc into POD and HTML manual-pages.  See README.md
# Copyright Mark Overmeer.  Licensed under the same terms as Perl itself.

#!!! This code is a mainly a rework of Dancer2::Template::TemplateToolkit,
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

has tt => ( is => 'rw', isa => InstanceOf ['Template'] );

sub _build_engine {
	my $self	  = shift;
	my $config	  = $self->config;
	my $charset   = $self->charset;
	my $templater = $config->{templater} || 'Log::Report::Template';

	my %tt_config = (
		ANYCASE  => 1,
		ABSOLUTE => 1,
		(length $charset) ? (ENCODING => $charset) : (),
		%$config,
	);

	my $start_tag = $config->{start_tag} || '[%';
	$tt_config{START_TAG} = $start_tag if $start_tag ne '[%';

	my $stop_tag  = $config->{stop_tag}  || $config->{end_tag} || '%]';
	$tt_config{END_TAG}   = $stop_tag  if $stop_tag ne '%]';

	weaken(my $ttt = $self);

	my $include_path = $config->{include_path};
	$tt_config{INCLUDE_PATH} ||= [
		( defined $include_path ? $include_path : () ),
		sub { [ $ttt->views ] },
	];

	$self->tt($templater->new(%tt_config));
	$Template::Stash::PRIVATE = undef if $config->{show_private_variables};
	$self;
}

sub addTextdomain(%) {
	my $self = shift;
	$self->tt->addTextdomain(@_);
}

sub render($$) {
	my ($self, $template, $tokens) = @_;
	my $content = '';
	my $charset = $self->charset;
	my @options = (length $charset) ? (binmode => ":encoding($charset)") : ();

	$self->tt->process($template, $tokens, \$content, @options)
		or $self->log_cb->(core => 'Failed to render template: ' . $self->engine->error);

	$content;
}

# Override *_pathname methods from Dancer2::Core::Role::Template
# Let TT2 do the concatenation of paths to template names.
#
# TT2 will look in a its INCLUDE_PATH for templates.
# Typically $self->views is an absolute path, and we set ABSOLUTE=> 1 above.
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

=pod

=encoding UTF-8

=head1 NAME

Dancer2::Template::TTLogReport - Template toolkit engine with Log::Report extension for Dancer2

=head1 SYNOPSIS

To use this engine, you may configure L<Dancer2> via C<config.yaml>:

    template:   "TTLogReport"

Or you may also change the rendering engine on a per-route basis by
setting it manually with C<set>:

    set template => 'TTLogReport';

=head1 DESCRIPTION

This template engine allows you to use L<Template>::Toolkit in L<Dancer2>,
including the translation extensions offered by L<Log::Report::Template>.

Most configuration variables available when creating a new instance of a
L<Template>::Toolkit object can be declared inside the template toolkit
section on the engines configuration in your config.yml file.  For example:

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

=head1 METHODS

=head2 render($template, \%tokens)

Renders the template.  The first arg is a filename for the template file
or a reference to a string that contains the template. The second arg
is a hashref for the tokens that you wish to pass to
L<Template::Toolkit> for rendering.

=head1 ADVANCED CUSTOMIZATION

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
          native_language: en-EN
          templater: Log::Report::Template  # default

=cut

