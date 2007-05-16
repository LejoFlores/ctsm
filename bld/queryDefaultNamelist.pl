#!/usr/bin/env perl
#=======================================================================
#
#  This is a script to read the CLM namelist XML file
#
# Usage:
#
# queryDefaultNamelist.pl [options]
#
# To get help on options and usage:
#
# queryDefaultNamelist.pl -help
#
#=======================================================================

use Cwd;
use strict;
#use diagnostics;
use Getopt::Long;
use English;

#-----------------------------------------------------------------------------------------------

#Figure out where configure directory is and where can use the XML/Lite module from
my $ProgName;
($ProgName = $PROGRAM_NAME) =~ s!(.*)/!!; # name of program
my $ProgDir = $1;                         # name of directory where program lives

my $cwd = getcwd();  # current working directory
my $cfgdir;

if ($ProgDir) { $cfgdir = $ProgDir; }
else { $cfgdir = $cwd; }
(-f "$cfgdir/XML/Lite.pm")  or  die <<"EOF";
** Cannot find perl module \"XML/Lite.pm\" in directory \"$cfgdir\" **
EOF

#-----------------------------------------------------------------------------------------------
# Add $cfgdir to the list of paths that Perl searches for modules
unshift @INC, $cfgdir;
require XML::Lite;

# Defaults
my $namelist = "clm_inparm";
my $file = "$cfgdir/DefaultCLM_INPARM_Namelist.xml";
my $config = "config_cache.xml";


sub usage {
    die <<EOF;
SYNOPSIS
     $ProgName [options]
OPTIONS
     -config "file"                       CLM build configuration file created by configure.
     -csmdata "dir"                       Directory for head of csm inputdata
     -file "file"                         Input xml file to read in by default ($file)
     -help  [or -h]                       Display this help
     -justvalue                           Just display the values (NOT key = value)
     -var "varname"                       Variable name to match
     -namelist "namelistname"             Namelist name to read in by default ($namelist)
     -onlyfiles                           Only output filenames
     -options "item=value,item2=value2"   Set options to query for when matching 
                                          (comma delimited, with equality to set value)
     -res  "resolution"                   Resolution to use for files
     -scpto "dir"                         Copy files to given directory
     -silent [or -s]                      Don't do any extra printing
     -test   [or -t]                      Test that files exists
EXAMPLES
 
  To list all fsurdat files that match the resolution: 10x15:
 
  $ProgName -var "fsurdat" -res 10x15
 
  To only list files that match T42 resolution (or are for all resolutions)
 
  $ProgName  -onlyfiles  -res 64x128
 
  To test that all of the files exist on disk under a different default inputdata
 
  $ProgName  -onlyfiles -test -csmdata /spin/proj/ccsm/inputdata
 
  To query the CAM file for files that match particular configurations
 
  $ProgName  -onlyfiles \
  -file \$CAM_CFGDIR/DefaultCAM_INPARM_Namelist.xml -namelist cam_inparm \
  -options DYNAMICS=fv,PLEV=26,PHYSICS=cam1,OCEANMODEL=DOM,CHEMISTRY=
 
  To copy files that match to a different location
 
  $ProgName -onlyfiles -test -scpto bangkok:/fs/cgd/csm/inputdata

EOF
}

#-------------------------------------------------------------------------------

sub convert_keys_touppercase
{
   my (%hash) = @_;

   my %outhash;
   foreach my $key ( keys(%hash) ) {
      $_ = $key;
      tr/a-z/A-Z/;
      $outhash{$_} = $hash{$key};
   }
   return( %outhash );
}

#-------------------------------------------------------------------------------

sub read_cfg_file
{
    my ($file) = @_;

    if ( ! -f "$file" ) {
      die "file $file does not exist\n";
    }
    my $xml = XML::Lite->new( $file );
    my $root = $xml->root_element();

    # Check for valid root node
    my $name = $root->get_name();
    $name eq "config_bld" or die
        "file $file is not a CLM configuration file\n";

    # Get source and build directories
    my $dirs = $xml->elements_by_name( "directories" );
    my %dirs = $dirs->get_attributes();
    my %DIRS = convert_keys_touppercase( %dirs );

    # Get cppvars
    my $cppvars = $xml->elements_by_name( "cppvars" );
    my %cppvars = $cppvars->get_attributes();
    my %CPPVARS = convert_keys_touppercase( %cppvars );

    # Get settings for Makefile (parallelism and library locations)
    my $make = $xml->elements_by_name( "makefile" );
    my %make = $make->get_attributes();
    my %MAKE = convert_keys_touppercase( %make );

    return %DIRS, %CPPVARS, %MAKE;
}

#-----------------------------------------------------------------------------------------------

  my %opts = ( file       => $file,
               namelist   => $namelist,
               var        => undef,
               res        => undef,
               config     => undef,
               csmdata    => undef,
               test       => undef,
               onlyfiles  => undef,
               justvalues => undef,
               scpto      => undef,
               silent     => undef,
               help       => undef,
               options    => undef,
             );

  GetOptions(
        "f|file=s"     => \$opts{'file'},
        "n|namelist=s" => \$opts{'namelist'},
        "v|var=s"      => \$opts{'var'},
        "r|res=s"      => \$opts{'res'},
        "config=s"     => \$opts{'config'},
        "csmdata=s"    => \$opts{'csmdata'},
        "options=s"    => \$opts{'options'},
        "t|test"       => \$opts{'test'},
        "onlyfiles"    => \$opts{'onlyfiles'},
        "justvalues"   => \$opts{'justvalues'},
        "scpto=s"      => \$opts{'scpto'},
        "s|silent"     => \$opts{'silent'},
        "h|elp"        => \$opts{'help'},
  ) or usage();

  # Check for unparsed arguments
  if (@ARGV) {
      print "ERROR: unrecognized arguments: @ARGV\n";
      usage();
  }
  if ( $opts{'help'} ) {
      usage();
  }
  $file = $opts{'file'};
  $namelist = $opts{'namelist'}; 
  my %bld;
  if ( defined( $opts{'config'} ) ) {
     %bld = read_cfg_file( $opts{'config'} );
  }

  # Set if should do extra printing or not (if silent mode is not set)
  my $printing = 1;
  if ( defined($opts{'silent'}) ) {
      $printing = 0;
  }
  # Get list of options from command-line into the settings hash
  my %settings;
  if ( defined($opts{'options'}) ) {
     my @optionlist = split( ",", $opts{'options'} );
     foreach my $item ( @optionlist ) {
        my ($key,$value) = split( "=", $item );
        $settings{$key} = $value;
     }
  }
  my $nm = $ProgName;
  print "($nm) Read: " . $opts{'file'} . "\n" if $printing;
  my $xml = XML::Lite->new( $opts{'file'} );
  if ( ! defined($xml) ) {
    die "ERROR($nm): Trouble opening or reading $opts{'file'}\n";
  }
  #
  # Find the namelist element for this namelist
  #
  my $elm = $xml->root_element( );
  my @list = $xml->elements_by_name( $namelist );
  if ( $#list < 0 ) {
    die "ERROR($nm): could not find the main $namelist namelist element in $file\n";
  }
  if ( $#list != 0 ) {
    die "ERROR($nm): $namelist namelist element in $file is duplicated, there should only be one\n";
  }
  $elm = $list[0];
  my @children = $elm->get_children();
  if ( $#children < 0 ) {
    die "ERROR($nm): There are no sub-elements to the $namelist element in $file\n";
  }
  #
  # Get the names for each element in the list into a hash
  #
  my %names;
  foreach my $child ( @children ) {
    my $name = $child->get_name();
    $names{$name} = $child->get_text();
  }
  #
  # Go through the sub-elements to the namelist element
  #
  foreach my $child ( @children ) {
    #
    # Get the attributes for each namelist element
    # The attributes describe either config settings that need to match
    # or other namelist elements that need to match
    #
    my %atts = $child->get_attributes;
    # Name of element, and it's associated value
    my $name = $child->get_name();
    my $value =  $child->get_text();
    $value =~ s/\n//g;   # Get rid of extra returns
    my @keys = keys(%atts);
    my $print = 1;
    if ( defined($opts{'var'}) ) {
       if ( $opts{'var'} ne $name ) {
          $print = undef;
       }
    }
    # If csmdata was NOT set on command line and file contains it
    if ( ! defined($opts{'csmdata'}) && ($name eq "csmdata") ) {
      $opts{'csmdata'} = $value;
    }
    if ( $#keys >= 0 ) {
      #
      # Check that all values match the appropriate settings
      #
      foreach my $key ( @keys ) {
         # Match resolution
         if ( defined($opts{'res'}) ) {
            if ( ($key eq "RESOLUTION") && ($atts{$key} ne $opts{'res'} ) ) {
               $print = undef;
            }
         }
         # Match any options set from command line
         if ( defined($opts{'options'}) ) {
            foreach my $optionkey ( keys(%settings) ) {
               if ( ($key eq "$optionkey") && ($atts{$key} ne $settings{$optionkey} ) ) {
                  $print = undef;
               }
            }
         }
         # Match any options from the build config file
         if ( defined($opts{'config'}) ) {
            foreach my $optionkey ( keys(%bld) ) {
               if ( ($key eq "$optionkey") && ($atts{$key} ne $bld{$optionkey} ) ) {
                  $print = undef;
               }
            }
         }
      }
    }
    my $isafile;
    #
    # If is a directory (has slashes, is csmdata or a var with dir in name)
    if ( $value =~ /\// && (($name eq "csmdata") || ($name =~ /dir/))  ) {
      if ( $name eq "csmdata" ) {
         $value = $opts{'csmdata'};
      }
      if ( $name eq "offline_atmdir" ) {
         $value = "$opts{'csmdata'}/$value";
      }
      # Test that this directory exists
      if ( defined($opts{'test'})  && defined($print) ) { 
         print "Test that directory $value exists\n" if $printing;
         if ( ! -d "$value" ) {
            die "($ProgName) ERROR:: directory $value does NOT exist!\n";
         }
      }
    #
    # Otherwise if it is a file (has slashes in value)
    #
    } elsif ( $value =~ /\// ) {
      my $filename = $value;
      $value = "$opts{'csmdata'}/$value";
      # Test that this file exists
      if ( defined($opts{'test'})  && defined($print) ) { 
         print "Test that file $value exists\n" if $printing;
         if ( ! -f "$value" ) {
            die "($ProgName) ERROR:: file $value does NOT exist!\n";
         }
      }
      # Copy to remote location
      if ( defined($opts{'scpto'}) && defined($print) ) { 
         print "scp $value $opts{'scpto'}/$filename\n";
         system( "scp $value $opts{'scpto'}/$filename" )
      }
      $isafile = 1;
    # For settings that are NOT files
    } else {
      $isafile = 0;
    }
    # If appears to be a string -- add quotes around the value
    if ( $value =~ /[^0-9.de+-]/ ) {
      $value = "\'$value\'";
    }
    # If onlyfiles option set do NOT print if is NOT a file
    if ( defined($opts{'onlyfiles'}) && (! $isafile) ) {
       $print = undef;
    }
    # Print out
    if ( defined($print) ) { 
       if ( ! defined($opts{'justvalues'})  ) {
          print "$name = ";
       }
       print "$value\n";
    }
  }
  if ( $printing && defined($opts{'test'}) ) {
     print "\n\nTesting was successful\n\n"
  }
 
