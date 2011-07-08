use Datascope;
require "getopts.pl" ;
#use strict;
#use warnings;
our $PROG_NAME;
($PROG_NAME = $0) =~ s(.*/)();	# PROG_NAME becomes $0 minus any path

######################################################################
#
# Vision:
#
# Read a ttgrid parameter file and produce a corresponding grid 
# regions database
####################################################################
#

# Usage - command line options and arguments
our ($opt_e);
if ( ! &Getopts('e') || ! $#ARGV == 0  ) {
        print STDERR <<"EOU" ;

        Usage: $PROG_NAME [-e] ttgridpf

        $PROG_NAME writes a grid regions database for all grids described 
	in a ttgrid parameter file

EOU
        exit 1 ;
}

use List::Util qw[min max];
use Avoseis::SwarmAlarm qw(runCommand getPf prettyprint );
use File::Basename;
$ttgridpffile = $ARGV[0];
$stationdb = "dbmaster/master_stations";
#use Env;

$gridregiondb = basename $ttgridpffile;
$gridregiondb =~ s/ttgrid/grid/;
$gridregiondb =~ s/\.pf//;
$gridregiondb = "regions/$gridregiondb";

print "GRIDREGIONDB = $gridregiondb\n";
if (-e $gridregiondb) {
        print "Delete existing $gridregiondb?\n";
        if (<STDIN> =~ /n/) {
                die("Cannot continue\n");
        }
}

unless (-e $gridregiondb) {
	open(FOUT, ">$gridregiondb");
	print FOUT<<EOF;
#
schema places1.2
dblocks none
EOF
}

system("touch $gridregiondb.regions");

@db = dbopen_table("$gridregiondb.regions", "r+");

############## This part is identical to ttgridwrapper ############################
$pfref = &getPf($ttgridpffile);

%allvars = %$pfref;
$gridsref = $allvars{"grids"};
%gridshash = %$gridsref;


foreach $gridname (keys %gridshash) {
	print "\nGrid = $gridname\n";
	$gridref = $gridshash{$gridname};
	%gridhash = %$gridref;
	#&prettyprint(%gridhash);
	foreach $key (keys %gridhash) {
		if (ref($gridhash{$key}) eq "ARRAY") {
			$arrref = $gridhash{$key};
			@arr = @$arrref;
			print "$key = { @arr }\n";
		}
		else
		{
			print "$key = $gridhash{$key}\n";
		}
	}

	$strike = $gridhash{'strike'};

	if ($strike) {
		#print "STRIKE!\n";
	}
	else
	{
		#print "No strike\n";
		$strike = 90.0;
	}

	$lonr = $gridhash{'lonr'};
	$latr = $gridhash{'latr'};
	$xmin = $gridhash{'xmin'};
	$xmax = $gridhash{'xmax'};
	$ymin = $gridhash{'ymin'};
	$ymax = $gridhash{'ymax'};

	@arrlon = [];
	@arrlat = [];

	# Vertex 1
	($tmplon, $tmplat) = &move_x($xmin, $strike, $lonr, $latr);
	($arrlon[0], $arrlat[0]) = &move_y($ymin, $strike, $tmplon, $tmplat);
	
	# Vertex 2 
	($tmplon, $tmplat) = &move_x($xmax, $strike, $lonr, $latr);
	($arrlon[1], $arrlat[1]) = &move_y($ymin, $strike, $tmplon, $tmplat);
	
	# Vertex 3 
	($tmplon, $tmplat) = &move_x($xmax, $strike, $lonr, $latr);
	($arrlon[2], $arrlat[2]) = &move_y($ymax, $strike, $tmplon, $tmplat);
	
	# Vertex 4 
	($tmplon, $tmplat) = &move_x($xmin, $strike, $lonr, $latr);
	($arrlon[3], $arrlat[3]) = &move_y($ymax, $strike, $tmplon, $tmplat);


############## This part is identical to ttgridwrapper ############################


	dbaddv(@db, 'regname', $gridname, 'vertex', 1, 'lon', $arrlon[0], 'lat', $arrlat[0]);
	dbaddv(@db, 'regname', $gridname, 'vertex', 2, 'lon', $arrlon[1], 'lat', $arrlat[1]);
	dbaddv(@db, 'regname', $gridname, 'vertex', 3, 'lon', $arrlon[2], 'lat', $arrlat[2]);
	dbaddv(@db, 'regname', $gridname, 'vertex', 4, 'lon', $arrlon[3], 'lat', $arrlat[3]);
}
dbclose(@db);


sub move_x {
	($xdeg, $strike, $lon, $lat) = @_;
	$newlon = `dbcalc -c "longitude($lat, $lon, $xdeg, $strike)"`; chomp($newlon);
	$newlat = `dbcalc -c "latitude($lat, $lon, $xdeg, $strike)"`; chomp($newlat);
	$newlon = sprintf("%.3f", $newlon);
	$newlat = sprintf("%.3f", $newlat);
	return ($newlon, $newlat);
}

sub move_y {
	($ydeg, $strike, $lon, $lat) = @_;
	$newlon = `dbcalc -c "longitude($lat, $lon, $ydeg, $strike-90.0)"`; chomp($newlon);
	$newlat = `dbcalc -c "latitude($lat, $lon, $ydeg, $strike-90.0)"`; chomp($newlat);
	$newlon = sprintf("%.3f", $newlon);
	$newlat = sprintf("%.3f", $newlat);
	return ($newlon, $newlat);
}
