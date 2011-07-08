eval 'exec perl -S $0 "$@"'
##############################################################################
# Author: Glenn Thompson (GT) 1998-1999 and 2007, UNIVERSITY OF ALASKA FAIRBANKS
#
# Modifications:
#
# Purpose:
#
# 	Creates/updates HTML & XML menus
##############################################################################

use Datascope;
#use orb;
use File::Basename;
use File::Copy qw(move copy);
require "getopts.pl" ;
 
use strict;
use warnings;
our $PROG_NAME;
($PROG_NAME = $0) =~ s(.*/)();	# PROG_NAME becomes $0 minus any path

# End of  GT Antelope Perl header
##############################################################################
use File::Path qw(mkpath);

# Usage - command line options and arguments
if ( ! &Getopts('l:v') || $#ARGV != 0  ) { 
    print STDERR <<"EOF" ;
    
    Usage: $PROG_NAME [-v] [-l logfile] PFDIR

	        -v      verbose
                -l      logfile, default iceweb.log in ICEWEB_HOME/LOGS

		PFDIR  is the path to the pf directory (e.g. ./pf)

EOF
    exit 1 ;
}

# Define variables
our $opt_v;		# Verbose flag
our $opt_l;		# logfile
our $logfile;
our %paths;
our($paths, $pathspf, $parameterspf, $subnetspf, @subnets);
our ($convert, $ALCHEMY); 
our %imageFormat;

# read paths
$paths{PFS} 		= $ARGV[0]; 
$pathspf 		= $paths{PFS}."/paths.pf"; 
$parameterspf		= $paths{PFS}."/iceweb_parameters.pf";
$subnetspf		= $paths{PFS}."/iceweb_subnets.pf";
$paths{ICEWEB_PLOTS_WEB}= 'www_iceweb2_op';
$paths{ICEWEB_URL}	= pfget($pathspf, "ICEWEB_URL");
$paths{DOCS}		= "http://www.avo.alaska.edu/wiki/index.php/IceWeb";

# other globals
$imageFormat{IN} 	= pfget($parameterspf, "imageFormat_matlab");
$imageFormat{OUT} 	= pfget($parameterspf, "imageFormat_web");
my $subnetsref		= pfget($subnetspf, "subnets");
@subnets		= @$subnetsref;
my $measurementsref = pfget($parameterspf, "measures");
our @measurements = @$measurementsref;

print `date`;

# Update the main html menu
my $menuxml = &update_iceweb_menu; 

########################################################

sub update_iceweb_menu {
	our (%paths, %imageFormat, @subnets);
	my $menuhtml = $paths{ICEWEB_PLOTS_WEB}."/iceweb_menu.html";

	my $pffile;

	# Derived data measurements variables
	my %labels = (
		"drs" => "Reduced Displacement",
		"tmdrs" => "Reduced Displacement",
	);
	my %id = ("drs" => "reduced", "tmdrs" => "reduced");

	# image format extension - not used
	my $extension = $imageFormat{OUT};
	

	############################################
	########### HTML MENU STARTS HERE ##########
	############################################

	print "\n**** Creating $menuhtml ****\n";
	open(FHTML, ">$menuhtml") or die("Cannot open $menuhtml for output\n");
	print FHTML "<head><title>IceWeb2 Website</title></head><body>";

	my ($subnet);
	my $baseurl = $paths{ICEWEB_URL}; 

	# Diagnostics page
	print FHTML "<p><a href=\"diagnostics.html\">IceWeb Diagnostics</a></p>";

	# spectrogram menu
	print FHTML "<p>Spectrograms</p>";
	foreach $subnet (@subnets) {
		print FHTML "$subnet: \n";
		print FHTML "<a href=\"$baseurl/html/sgram10min.php?subnet=$subnet\">10min</a> \n";
		print FHTML "<a href=\"$baseurl/html/mosaicMakerHoursAgo.php?subnet=".$subnet."&starthour=2&endhour=0\">mosaic</a>\n";
		print FHTML "<a href=\"http://kiska.giseis.alaska.edu/internal/ICEWEB/SPECTROGRAMS/".$subnet."/currentday.gif\">today</a>\n";
		print FHTML "<a href=\"http://kiska.giseis.alaska.edu/internal/ICEWEB/SPECTROGRAMS/".$subnet."/lastday.gif\">yesterday</a>\n";
		print FHTML "<br/>\n";
	}

	# derived data plots menus


	foreach my $measurement (@measurements) {
		print FHTML "<p>".$labels{$measurement}."</p>";
		foreach $subnet (@subnets) {
			print FHTML "$subnet: \n";
			foreach my $days (&read_dayplots($subnet)) {
				my $hours = int($days * 24);
				my $tstr = $days."_days";
				$tstr = $hours."_hours" if ($days < 1);
				print FHTML "<a href=\"$baseurl/html/dr.php?subnet=$subnet&amp;days=$days&amp;map=HideMap&amp;plot=LogPlot\">$tstr</a> \n";
			}
			print FHTML "<br/>\n";
		
		}
		print FHTML "<p/>\n";
	}	

	print FHTML "</body></html>";	 
	close(FHTML);	


	############################################
	########### XML MENU STARTS HERE ##########
	############################################

	(my $menuxml = $menuhtml) =~ s/html/xml/;
	print "\n**** Creating $menuxml ****\n";
	open(FXML, ">$menuxml") or die("Cannot open $menuxml for output\n");
	print FXML "<?xml version=\"1.0\" encoding=\"ISO-8859-1\"?>\n";
	print FXML "<data>\n";

	

	# spectrogram menu
	print FXML "\t<section name=\"Spectrograms\" id=\"spectrograms\">\n";
	foreach $subnet (@subnets) {
		print FXML "\t\t<subnet name=\"$subnet\">\n";
		print FXML "\t\t\t<link url=\"$baseurl/html/sgram10min.php?subnet=$subnet\" label=\"10min\" />\n";
		print FXML "\t\t\t<link url=\"$baseurl/html/mosaicMakerHoursAgo.php?subnet=".$subnet."&amp;starthour=2&amp;endhour=0\" label=\"mosaic\" />\n";
		print FXML "\t\t\t<link url=\"http://kiska.giseis.alaska.edu/internal/ICEWEB/SPECTROGRAMS/".$subnet."/currentday.gif\" label=\"today\" />\n";
		print FXML "\t\t\t<link url=\"http://kiska.giseis.alaska.edu/internal/ICEWEB/SPECTROGRAMS/".$subnet."/lastday.gif\" label=\"yesterday\"/>\n";
		print FXML "\t\t</subnet>\n";
	}
	print FXML "\t</section>\n";

	# derived data plots menus
	foreach my $measurement (@measurements) {
		if ($measurement =~ /drs/) {
			if (-e $paths{ICEWEB_PLOTS_WEB}."/plots/drs") {
				system("rm ".$paths{ICEWEB_PLOTS_WEB}."/plots/drs");
			}
			system("ln -s ".$paths{ICEWEB_PLOTS_WEB}."/plots/$measurement ".$paths{ICEWEB_PLOTS_WEB}."/plots/drs");
		}
		print FXML "\t<section name=\"".$labels{$measurement}."\" id=\"".$measurement."\">\n";
		foreach $subnet (@subnets) {
			print FXML "\t\t<subnet name=\"$subnet\">\n";
			foreach my $days (&read_dayplots($subnet)) {
				my $hours = int($days * 24);
				my $tstr = $days."_days";
				$tstr = $hours."_hours" if ($days < 1);
				print FXML "\t\t\t<link url=\"$baseurl/html/dr.php?subnet=$subnet&amp;days=$days&amp;map=HideMap&amp;plot=LogPlot\" label=\"$tstr\" />\n";
			}
			print FXML "\t\t</subnet>\n";
		
		}
		print FXML "\t</section>\n";
	}


	print FXML "\t<section name=\"Links\" id=\"links\">\n";
	print FXML "\t\t\t<link url=\"$baseurl/iceweb_menu.html\" label=\"HTML Menu\" /><br/>\n";
	print FXML "\t\t\t<link url=\"$baseurl/diagnostics.html\" label=\"Diagnostics\" />\n";
	print FXML "\t</section>\n";

	# end the data section
	print FXML "</data>\n";

	# close the XML file		 
	close(FXML);

	# return menu_xml
	return $menuxml;	

}




########################################################

sub read_dayplots {
	our (%paths, $parameterspf);
	my @drplots;
	my $subnet = $_[0];
	my $pf=$paths{PFS}."/subnet_$subnet.pf";
	my $ref=pfget($pf,"day_plots");
	if (defined($ref)) {
		@drplots=@$ref;
	}
	else
	{
		my $ref=pfget($parameterspf,"day_plots");
		@drplots=@$ref;
	}

	return @drplots;
}

