#!/usr/bin/perl

=head1 NAME

load_images.pl

=head1 SYNOPSYS

load_images.pl [ sandbox | cxgn | trial ] dirname

=head1 DESCRIPTION

Loads tomato images from the Van der Knaap lab into the SGN database, using the SGN::Image framework. 
    

Requires the following parameters: 

=over 5

=item 

a database parameter, which can either be "cxgn", "sandbox", or "trial". "cxgn" and "sandbox" will cause the script to connect to the respective databases; "trial" will connect to sandbox, but not perform any of the database modifications. 

=item

a dirname that contains subdirectories named after database accessions, containing one or more images.

=back

The script will generate an error file, named like the filename supplied, with the extension .err.

=head1 AUTHOR(S)

Naama Menda (nm249@cornell.edu) March 2010.

=cut

use strict;

use CXGN::DB::InsertDBH;
use SGN::Image;
use CXGN::Phenome::Individual;
use CXGN::Phenome::Population;
use CXGN::People::Person;

use File::Basename;
use SGN::Context;
use Getopt::Std;


our ($opt_H, $opt_D, $opt_t, $opt_i, $opt_u, $opt_p);

getopts('H:D:u:ti:p:');

my $dbhost = $opt_H;
my $dbname = $opt_D;
my $dirname = $opt_i;
my $sp_person=$opt_u;

my $population_name = $opt_p;

if (!$dbhost && !$dbname) { 
    usage();
}

if (!$dirname) { usage(); }

my $dbh = CXGN::DB::InsertDBH->new( { dbhost=>$dbhost,
				      dbname=>$dbname,
				    } );

my $sp_person_id= CXGN::People::Person->get_person_by_username($dbh, $sp_person);
my %name2id = ();

my $POPULATION_ID=0;


my $ch = SGN::Context->new();
my $image_dir = $ch->get_conf("image_dir");

print "PLEASE VERIFY:\n";
print "Using dbhost: $dbhost. DB name: $dbname. \n";
print "Path to image is: $image_dir\n";
print "CONTINUE? ";
my $a = (<STDIN>);
if ($a !~ /[yY]/) { exit(); }

if (($dbname eq "sandbox") && ($image_dir !~ /sandbox/)) { 
    die "The image directory needs to be set to image_files_sandbox if running on rubisco/sandbox. Please change the image_dir parameter in SGN.conf\n\n";
}
if (($dbname eq "cxgn") && ($image_dir =~ /sandbox/)) { 
    die "The image directory needs to be set to image_files when the script is running on the production database. Please change the image_dir parameter in SGN.conf\n\n";
}

my $pop_name= $opt_p || 'Tomato Cultivars and Heirloom lines' ;
print STDOUT "Fetching population $pop_name\n";

my $population=CXGN::Phenome::Population->new_with_name($dbh, $pop_name);
my $population_id = $population->get_population_id() ;
$sp_person_id = $population->get_sp_person_id() if !$sp_person_id;

if (!$population_id) { die "Can't find the population $pop_name'!"; }

$POPULATION_ID=$population_id;
print STDOUT "Working with population id $POPULATION_ID.\n";
my %image_hash = ();  # used to retrieve images that are already loaded by have new accessions
my %connections = (); # keep track of accession -- image connections that have already been made.

    
# get the individual id from the database.
# the individual name is coded in the image file name.
#
print STDERR "Getting the individuals from the database...\n";

my @individuals=$population->get_individuals();
foreach my $i(@individuals) {
    my $id= $i->get_individual_id();
    my $name=$i->get_name();
    $name2id{lc($name)}=$id;
}

# cache image individual image links to prevent reloading of the
# same data
#
print STDERR "Caching image individual links...\n";

my $q2 = "SELECT image_id, individual_id FROM md_image join individual_image using (image_id) JOIN phenome.individual using (individual_id)";
my $s2 = $dbh->prepare($q2);
$s2->execute();
while (my ($image_id, $individual_id) = $s2->fetchrow_array()) { 
    my $i = SGN::Image->new($dbh, $image_id);
    my $original_filename = $i->get_original_filename();
    $image_hash{$original_filename} = $i; # this doesn't have the file extension
    $connections{$image_id."-".$individual_id}++;
}

open (ERR, ">$opt_i" . ".err") || die "Can't open error file\n";

my @files = `ls $dirname/*.jpg`;

my $new_individual_count = 0;
my $new_image_count = 0;


foreach my $file (@files) { 
    eval { 
	chomp($file);
	print STDOUT "Processing file $file...\n";
	
	my $individual_name = basename($file);
	
	#$individual_name =~s/(W\d{3,4}).*\.JPG/$1/i if $individual_name =~m/^W\d{3}/;
	($individual_name, undef ) =  split /_/, $individual_name;
	if (!$individual_name) { die "File $file has no individual name in it!"; }
	
	print STDOUT "Loading $individual_name, image $file\n";
	print ERR "Loading $individual_name, image $file\n";
	
	if (! -e $file) { 
	    die "The specified file $file does not exist! Skipping...\n";
	}
	
	
	if (!exists($name2id{lc($individual_name)})) { 
	    
	    message ("$individual_name does not exist in the database...\n");
	    #message("Adding individual $individual_name...\n");
	    
	   # if ($opt_t) { 
	#	print STDOUT "Trial parse: would load individual $individual_name...\n";
	#	$new_individual_count++;
	   # }
	   # else { 
	#	my $new_individual = CXGN::Phenome::Individual->new($dbh);
	#	$new_individual->set_population_id($POPULATION_ID);
	#	$new_individual->set_name($individual_name);
	#	my $id = 0;
	#	if ($id = $new_individual->store()) { 
	#	    print STDOUT "Stored individual successfully...\n";
	#	}
	#	$name2id{lc($individual_name)}=$id;
	#	$new_individual_count++;
	#    }
	}
	
	else {
	    print ERR "Adding $file...\n";
	    if (exists($image_hash{$file})) { 
		print ERR "$file is already loaded into the database...\n";
		my $image_id = $image_hash{$file}->get_image_id();
		$connections{$image_id."-".$name2id{lc($individual_name)}}++;
		if ($connections{$image_id."-".$name2id{lc($individual_name)}} > 1) { 
		    print ERR "The connection between $individual_name and image $file has already been made. Skipping...\n";
		}
		elsif ($image_hash{$file}) { 
		    print ERR qq  { Associating individual $name2id{lc($individual_name)} with already loaded image $file...\n };
		    $image_hash{$file}->associate_individual($name2id{lc($individual_name)});
		}
	    }
	    else { 
		print ERR qq { Generating new image object for image $file and associating it with individual $individual_name, id $name2id{lc($individual_name)} ...\n };
		my $caption = $individual_name;
		
		
		if ($opt_t)  { 
		    print STDOUT qq { Would associate file $file to individual $individual_name, id $name2id{lc($individual_name)}\n };
		    $new_image_count++;
		}
		else { 
		    my $image = SGN::Image->new($dbh);   
		    $image_hash{$file}=$image;
		    
		    $image->process_image("$file", "individual", $name2id{lc($individual_name)}); 
		    $image->set_description("$caption");
		    $image->set_name(basename($file));
		    $image->set_sp_person_id($sp_person_id);
		    $image->set_obsolete("f");
		    $image->store();
		    $new_image_count++;
		}
	    }
	}
    };
    
    if ($@) { 
	print STDOUT "ERROR OCCURRED WHILE SAVING NEW INFORMATION. $@\n";
	$dbh->rollback();
    }
    else { 
	$dbh->commit();
    }
}




close(ERR);
close(F);




print STDOUT "Inserted  $new_image_count images.\n";
print STDOUT "Done. \n";

sub usage { 
    print "Usage: load_images.pl -D dbname [ cxgn | sandbox ]  -H dbhost -t [trial mode ] -i input dir -p population name (must be the same as the name in the database)\n";
    exit();
}

sub message {
    my $message=shift;
    print STDOUT $message;
    print ERR $message;
}
