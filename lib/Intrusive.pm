use strict;
package Intrusive;
use Cwd qw( getcwd );
use ExtUtils::MakeMaker ();
use Parse::CPAN::Meta;
use Cwd qw( getcwd );
use base qw( Class::Accessor::Chained );
__PACKAGE__->mk_accessors(qw( dist_dir debug libs requires build_requires error ));

sub new {
    my $self = shift;

    return $self->SUPER::new({
        libs           => [],
        requires       => {},
        build_requires => {},
        error          => '',
    });
}

sub find_modules {
    my $self = shift;

    my $here = getcwd;
    unless (chdir $self->dist_dir) {
        $self->error( "couldn't chdir to " . $self->dist_dir . ": $!" );
        return $self;
    }
    eval { $self->_find_modules };
    chdir $here;
    die $@ if $@;

    return $self;
}

sub _find_modules {
    my $self = shift;

    # this order is important, as when a Makefile.PL and Build.PL are
    # present, the Makefile.PL could just be a passthrough
    my $pl = -e 'Build.PL' ? 'Build.PL' : -e 'Makefile.PL' ? 'Makefile.PL' : 0;
    unless ($pl) {
        $self->error( 'No {Build,Makefile}.PL found in '.$self->dist_dir );
        return $self;
    }

    # avoid downloads in configure!
    $ENV{HTTP_PROXY}  = "http://9.9.9.9";
    # fake up Module::Build and ExtUtils::MakeMaker
    no warnings 'redefine';
    local *STDIN; # run non-interactive
    local *STDOUT;
    local *ExtUtils::Liblist::ext = sub {
        my ($class, $lib) = @_;
        $lib =~ s/\-l//;
        push @{ $self->libs }, $lib;
        return 1;
    };
    local *CORE::GLOBAL::exit = sub { };
    local $INC{"Module/Build.pm"} = 1;
    local @MyModuleBuilder::ISA = qw( Module::Build );
    local *Module::Build::new = sub {
        my $class = shift;
        my %args =  @_;
        $self->requires( $args{requires} || {} );
        $self->build_requires( $args{build_requires} || {} );
        bless {}, "Intrusive::Fake::Module::Build";
    };
    local *Module::Build::subclass = sub { 'Module::Build' };
    local $Module::Build::VERSION = 666;

    my $WriteMakefile = sub {
        my %args = @_;
        $self->requires( $args{PREREQ_PM} || {} );
        my %br = %{ $args{TEST_REQUIRES} || {} };
        %br = (%br, %{ $args{BUILD_REQUIRES} }) if $args{BUILD_REQUIRES};
        $self->build_requires( \%br );
        1;
    };
    local *main::WriteMakefile;
    local *ExtUtils::MakeMaker::WriteMakefile = $WriteMakefile;

    # Inline::MakeMaker
    local $INC{"Inline/MakeMaker.pm"} = 1;

    local @Inline::MakeMaker::EXPORT = qw( WriteMakefile WriteInlineMakefile );
    local @Inline::MakeMaker::ISA = qw( Exporter );
    local *Inline::MakeMaker::WriteMakefile = $WriteMakefile;
    local *Inline::MakeMaker::WriteInlineMakefile = $WriteMakefile;

    # Module::Install
    local $INC{"inc/Module/Install.pm"} = 1;
    local @inc::Module::Install::ISA = qw( Exporter );
    local @inc::Module::Install::EXPORT = qw(

      all_from auto_install AUTOLOAD build_requires check_nmake include
      include_deps installdirs Makefile makemaker_args Meta name no_index
      requires WriteAll clean_files can_cc sign cc_inc_paths cc_files
      cc_optimize_flags author license

    );
    local *inc::Module::Install::AUTOLOAD = sub { 1 };
    local *inc::Module::Install::requires = sub {
        my %deps = (@_ == 1 ? ( $_[0] => 0 ) : @_);
        $self->requires->{ $_ } = $deps{ $_ } for keys %deps;
    };
    local *inc::Module::Install::include_deps = *inc::Module::Install::requires;
    local *inc::Module::Install::build_requires = sub {
        my %deps = (@_ == 1 ? ( $_[0] => 0 ) : @_);
        $self->build_requires->{ $_ } = $deps{ $_ } for keys %deps;
    };

    my $file = File::Spec->catfile( getcwd(), $pl );
    eval {
        package main;
        no strict;
        no warnings;
        $SIG{ALRM} = sub { die "Timeout"; };
        alarm 5;
	local $0 = $file;
        do "$file";
        alarm 0;
    };
    $self->error( $@ ) if $@;
    delete $INC{$file};
    return $self;
}

package Intrusive::Fake::Module::Build;
sub DESTROY {}
sub AUTOLOAD { shift }
sub y_n {
    my ($self, $question, $default) = @_;
    $default ||= 'n';
    return 1 if lc $default eq 'y';
    return 0; # ok, we may say no when yes was intended, but we can't hang
}

package
   Term::ReadLine;
sub new { print "FAIL\n"; }

1;

__END__

=head1 NAME

Module::Depends::Intrusive - intrusive discovery of distribution dependencies.

=head1 SYNOPSIS

 # Just like Module::Depends, only use the Intrusive class instead

=head1 DESCRIPTION

This module devines dependencies by running the distributions
Makefile.PL/Build.PL in a faked up environment and intercepting the
calls to Module::Build->new and ExtUtils::MakeMaker::WriteMakefile.

You may now freak out about security.

While you're doing that please remember that what we're doing is much
the same that CPAN.pm does in order to discover prerequisites.

=head1 AUTHOR

Richard Clamp, based on code extracted from the Fotango build system
originally by James Duncan and Arthur Bergman.

=head1 COPYRIGHT

Copyright 2004 Fotango.  All Rights Reserved.

This module is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 SEE ALSO

L<Module::Depends>

=cut
