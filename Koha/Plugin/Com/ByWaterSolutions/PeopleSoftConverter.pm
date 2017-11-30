package Koha::Plugin::Com::ByWaterSolutions::PeopleSoftConverter;

## It's good practive to use Modern::Perl
use Modern::Perl;

## Required for all plugins
use base qw(Koha::Plugins::Base);

use File::Basename;
use DateTime;
use Text::CSV;

use open qw(:utf8);

## Here we set our plugin version
our $VERSION = "{VERSION}";

## Here is our metadata, some keys are required, some are optional
our $metadata = {
    name            => 'IBA Karachi PeopleSoft Patron File Converter',
    author          => 'Kyle M Hall',
    description     => 'This plugin converts the patron files from PeopleSoft into Koha compatiable files',
    date_authored   => '2015-04-01',
    date_updated    => '2009-04-01',
    minimum_version => '3.0100107',
    maximum_version => undef,
    version         => $VERSION,
};

## This is the minimum code required for a plugin's 'new' method
## More can be added, but none should be removed
sub new {
    my ( $class, $args ) = @_;

    ## We need to add our metadata here so our base class can access it
    $args->{'metadata'} = $metadata;
    $args->{'metadata'}->{'class'} = $class;

    ## Here, we call the 'new' method for our base class
    ## This runs some additional magic and checking
    ## and returns our actual $self
    my $self = $class->SUPER::new($args);

    return $self;
}

## The existance of a 'tool' subroutine means the plugin is capable
## of running a tool. The difference between a tool and a report is
## primarily semantic, but in general any plugin that modifies the
## Koha database should be considered a tool
sub tool {
    my ( $self, $args ) = @_;

    my $cgi = $self->{'cgi'};

    unless ( $cgi->param('peoplesoft') ) {
        $self->tool_step1();
    }
    else {
        $self->tool_step2();
    }

}

## This is the 'install' method. Any database tables or other setup that should
## be done when the plugin if first installed should be executed in this method.
## The installation method should always return true if the installation succeeded
## or false if it failed.
sub install() {
    my ( $self, $args ) = @_;

    return 1;
}

## This method will be run just before the plugin files are deleted
## when a plugin is uninstalled. It is good practice to clean up
## after ourselves!
sub uninstall() {
    my ( $self, $args ) = @_;

    return 1;
}

sub tool_step1 {
    my ( $self, $args ) = @_;
    my $cgi = $self->{'cgi'};

    my $template = $self->get_template( { file => 'tool-step1.tt' } );

    print $cgi->header();
    print $template->output();
}

sub tool_step2 {
    my ( $self, $args ) = @_;
    my $cgi = $self->{'cgi'};

    my $filename = $cgi->param("peoplesoft");
    warn "FILENAME: $filename";
    my ( $name, $path, $extension ) = fileparse( $filename, '.csv' );
    warn "NAME: $name";
    warn "PATH: $path";
    warn "EXT: $extension";

    my $map = {
        'cardnumber'        => 'EMPLID',
        'categorycode'      => 'ACAD_CAREER',
        'dateenrolled'      => \&calculate_dateenrolled,
        'gender'            => 'SEX',
        'firstname'         => 'LAST_NAME_SRCH',
        'surname'           => 'FIRST_NAME_SRCH',
        'branchcode'        => 'CAMPUS',
        'address'           => 'ADDRESS1',
        'address2'          => 'ADDRESS2',
        'city'              => 'CITY',
        'email'             => 'EMAIL_ADDR',
        'phone'             => 'PHONE',
        'country'           => 'COUNTRY',
        'dateexpiry'        => \&calculate_dateexpiry,
        'patron_attributes' => 'PROG:ACAD_PROG',
        'userid'            => 'EMPLID',
        'password'          => 'FIRST_NAME_SRCH',
    };

    my $csv_contents;
    open my $fh_out, '>', \$csv_contents or die "Can't open variable: $!";

    my $csv = Text::CSV->new( { binary => 1 } )
      or die "Cannot use CSV: " . Text::CSV->error_diag();
    $csv->eol("\r\n");

    $csv->print( $fh_out, [ keys %$map ] );

    my $upload_dir        = '/tmp';
    my $upload_filehandle = $cgi->upload("peoplesoft");
    open( UPLOADFILE, '>', "$upload_dir/$filename" ) or die "$!";
    binmode UPLOADFILE;
    while (<$upload_filehandle>) {
        print UPLOADFILE;
    }
    close UPLOADFILE;
    open my $fh_in, '<', "$upload_dir/$filename" or die "Can't open variable: $!";

    my $column_names = $csv->getline($fh_in);
    $csv->column_names(@$column_names);

    while ( my $hr = $csv->getline_hr($fh_in) ) {
        my @row = map { get_value( $_, $map, $hr ) } keys %$map;
        $csv->print( $fh_out, \@row );
    }

    $csv->eof or $csv->error_diag();
    close $fh_in;

    print("Content-Type:application/x-download\n");
    print "Content-Disposition: attachment; filename=$name-converted$extension\n\n";
    print $csv_contents;

}

sub get_value {
    my ( $output_key, $map, $hr ) = @_;

    my $input_key = $map->{$output_key};

    my $return;

    if ( $output_key =~ /^patron_attribute/ ) {
        my ( $attribute_name, $input_key ) = split( /:/, $map->{$output_key} );

        $return = $attribute_name . ":" . $hr->{$input_key};
    }
    elsif ( ref($input_key) eq 'CODE' ) {
        $return = $input_key->( $output_key, $map, $hr );
    }
    else {
        $return = $hr->{$input_key};
    }

    return $return;
}

sub calculate_dateexpiry {
    my ( $key, $map, $hr ) = @_;

    my $dateenrolled = calculate_dateenrolled(@_);

    my ( $year, $month, $day ) = split( /-/, $dateenrolled );

    my $type = $hr->{ACAD_CAREER};

    my $years =
        $type eq 'UGRD' ? 4
      : $type eq 'GRAD' ? 2
      : $type eq 'PGRD' ? 3
      : $type eq 'PDIP' ? 1
      :                   0;

    $year += $years;

    return "$year-$month-$day";
}

sub calculate_dateenrolled {
    my ( $key, $map, $hr ) = @_;

    my $admit_term = $hr->{ADMIT_TERM};

    my $year = '20' . substr( $admit_term, 0, 2 );

    my $semester = substr( $admit_term, 3, 1 );
    $semester =
        $semester == 1 ? 'spring'
      : $semester == 2 ? 'summer'
      : $semester == 3 ? 'fall'
      :                  undef;

    my ( $day, $month );
    if ( $semester eq 'spring' ) {
        $day   = '01';
        $month = '02';
    }
    elsif ( $semester eq 'summer' ) {
        $day   = '30';
        $month = '06';
    }
    elsif ( $semester eq 'fall' ) {
        $day   = '31';
        $month = '08';
    }

    return "$year-$month-$day";
}

1;
