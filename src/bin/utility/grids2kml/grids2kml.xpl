eval 'exec perl -S $0 "$@"'
use Datascope;
require "getopts.pl" ;
use strict;
#use warnings;
our $PROG_NAME;
($PROG_NAME = $0) =~ s(.*/)();	# PROG_NAME becomes $0 minus any path

######################################################################
#
# Vision:
#
# Load list of 52 historically active volcanoes, all stations within
# (say) 20 km of those, and map regions and grid regions
# produce KML file of volcanoes, stations, map regions and grid regions
# produce parameter files including:
#	avo_subnets.pf (list of volcanoes)
#	subnet_Redoubt.pf (list of stations & their locations & distances - and later their status)
#	ttgrid_Redoubt.pf (using information from grid regions)
#
# Next steps:
#	1. Get it to write valid KML (make use of <Document>)
# 	2. Read stations in array of hashes, separate function to write KML
#	3. Add parameter file routines
#	4. Add grid file regions to database
#
# 1. KML for historically active volcanoes + stations within 20 km or 5 closest stations
# 2. Station maps + fly-through
# 3. KML for avogrid
# 4. KML for aeicgrid
#
####################################################################

# Usage - command line options and arguments
if (  $#ARGV > -1 ) {
        print STDERR <<"EOU" ;

        Usage: $PROG_NAME 

        $PROG_NAME creates a KML file containing:
	- placemarks of historical active volcanoes
	- boxes of station maps as used on internal web page
	- grids used by AEIC and AVO

EOU
        exit 1 ;
}

use List::Util qw[min max];
use Avoseis::SwarmAlarm qw(runCommand prettyprint);

my $stationdb = "dbmaster/master_stations";
my $gridregiondb_avo = "regions/grid_avonew";
#my $gridregiondb_aeic = "regions/grid_local_aeic";

############## Open the KML file and print header and styles
use Env;
my $view_lat = 58;
my $view_lon = -153;
my $view_range = 2000000;
my $kmlfile = $ENV{'INTERNALWEBPRODUCTS'}."/data/kml/$PROG_NAME.kml";
my $kmlfilecopy = $ENV{'PUBLICWEBPRODUCTS'}."/kml/$PROG_NAME.kml";
print "Writing to $kmlfile\n";
open(FKML,">$kmlfile") or die("Cannot open $kmlfile\n");
print FKML &kml_header("$PROG_NAME");
print FKML &get_legend;

print FKML "<Folder>\n<name>detectionstations</name>\n";
print FKML "<visibility>0</visibility>\n";
print FKML "<LookAt><longitude>".$view_lon."</longitude><latitude>".$view_lat."</latitude><altitude>0</altitude><range>".$view_range."</range><tilt>0</tilt><heading>0</heading></LookAt>\n";
&orbdetectstations2kml();
print FKML "</Folder>\n";

# Add travel time grids from Antelope real-time system
print FKML "<Folder>\n<name>grids_avo</name>\n";
print FKML "<visibility>0</visibility>\n";
print FKML "<LookAt><longitude>".$view_lon."</longitude><latitude>".$view_lat."</latitude><altitude>0</altitude><range>".$view_range."</range><tilt>0</tilt><heading>0</heading></LookAt>\n";
print FKML &get_grids($gridregiondb_avo);
print FKML "</Folder>\n";

#print FKML "<Folder>\n<name>grids_aeic</name>\n";
#print FKML "<visibility>0</visibility>\n";
#print FKML "<LookAt><longitude>".$view_lon."</longitude><latitude>".$view_lat."</latitude><altitude>0</altitude><range>".$view_range."</range><tilt>0</tilt><heading>0</heading></LookAt>\n";
#print FKML &get_grids($gridregiondb_aeic);
#print FKML "</Folder>\n";

# Close the KML document
print FKML "</Document>\n";
print FKML &kml_footer();
close(FKML);

# Produce a copy of the file on the public server
&runCommand("cp $kmlfile $kmlfilecopy", 1);

########################################################################

sub get_grids {
	my ($gridregiondb) = @_;
	my $outstr = "";
	my $linestyle;
	my @db = dbopen_table("$gridregiondb.regions", "r") or die("Cannot open $gridregiondb.regions\n");
	my $nrows = dbquery(@db, "dbRECORD_COUNT");
	my @vertices = [];
	my $prev_regname = "";
	my $vindex = 0;
	for (my $k = 0; $k < $nrows; $k++) {
		$db[3] = $k;
		my ($regname, $vertex, $lat, $lon) = dbgetv(@db, 'regname', 'vertex', 'lat', 'lon');
		#print "regname = $regname, vertex = $vertex, lon = $lon, lat = $lat\n";
		my $vertexref = {lat => $lat, lon => $lon};
		if ($regname eq $prev_regname || $prev_regname eq "") {
			#print "Adding vertex $vindex\n";
			$vertices[$vindex++] = $vertexref; # should be an anonymous hash with lat & lon keys
		}
		else
		{	
			if ($prev_regname ne "") {	
				$linestyle = "linestyle_logrid";
				$linestyle = "linestyle_reggrid" if ($prev_regname =~ /reg/);
				#$outstr .= &kml_polygon($prev_regname." grid", $polystyle, @vertices);
				$outstr .= &kml_linestring($prev_regname." grid", $linestyle, @vertices);

				@vertices = [];
				$vindex = 0;
				$vertices[$vindex++] = $vertexref; # should be an anonymous hash with lat & lon keys
			}
		}
		$prev_regname = $regname;
	}
	dbclose(@db);

	# deal with last row too
	$linestyle = "linestyle_logrid";
	$linestyle = "linestyle_reggrid" if ($prev_regname =~ /reg/);

	#$outstr .= &kml_polygon($prev_regname." grid", $polystyle, @vertices); # if ($#vertices == 3);
	$outstr .= &kml_linestring($prev_regname." grid", $linestyle, @vertices);

	return $outstr;
}

sub orbdetectstations2kml {
	#my $dbname = "dborbdetect";
	my $dbname = "dbmaster/detection_stations";
	my @db = dbopen_table("$dbname.site", "r");
	my @db2 = dbopen_table("$dbname.sitechan", "r");
        @db = dbjoin(@db, @db2);
        @db2 = dbopen_table("$dbname.snetsta", "r");
        @db = dbjoin(@db, @db2);
        my $nstations = dbquery(@db, "dbRECORD_COUNT");
        my $laststa = "DUMM";
        for (my $j=0; $j < $nstations; $j++) {
                $db[3] = $j;
                my ($sta, $lat, $lon, $elev, $snet, $chan, $staname) = dbgetv(@db, "sta", "lat", "lon", "elev", "snet", "chan", "staname");
		my $desc = "";
        	my $desc=<<"EOD";

		<![CDATA[
			<b>$staname</b><br/>
			$sta $chan $snet<br/>
			lon=$lon, lat=$lat, elev=$elev<br/>
		]]>
EOD

		print FKML &kml_placemark($sta, $lat, $lon, $elev, $desc, "station", 0, 10.0, 20000, 0, 0, "absolute");
	}
	dbclose(@db);
	return 1;
}

	
#################################################################
### KML_HEADER
###
### $str = &kml_header($kmldoc_name);
#################################################################

sub kml_header {
        my $DOCUMENTNAME = $_[0];
        my $str =<<"EOF";
<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2"
 xmlns:gx="http://www.google.com/kml/ext/2.2">
<Document>
        <name>$DOCUMENTNAME</name>

        <LookAt><longitude>$view_lon</longitude><latitude>$view_lat</latitude><altitude>0</altitude><range>$view_range</range><tilt>0</tilt><heading>0</heading></LookAt>

        <Style id="station">
                <IconStyle><Icon><href>http://www.avo.alaska.edu/eq/kml/icons/seismometer_2.png</href></Icon></IconStyle>
                <LabelStyle><scale>0.4</scale></LabelStyle>
                <BalloonStyle><text>$[description]</text><bgColor>ffffffff</bgColor></BalloonStyle>
        </Style>

        <Style id="linestyle_logrid">
                <LineStyle>
                        <color>7f00ff00</color>
                        <width>4</width>
                </LineStyle>
        </Style>

        <Style id="linestyle_reggrid">
                <LineStyle>
                        <color>7fff0000</color>
                        <width>4</width>
                </LineStyle>
        </Style>
        
	<Style id="polystyle_avogrid">
                <LineStyle>
                        <color>7f00ff00</color>
                        <width>4</width>
                </LineStyle>
                <PolyStyle>
                        <color>7f00ff00</color>
                </PolyStyle>
        </Style>

        <Style id="polystyle_aeicgrid">
                <LineStyle>
                        <color>7fff0000</color>
                        <width>4</width>
                </LineStyle>
                <PolyStyle>
                        <color>7fff0000</color>
                </PolyStyle>
        </Style>
EOF


        return $str;
}

##################################################################################
### KML_PLACEMARK
###
### $str = &kml_placemark($placename, $lat, $lon, $elev, $description, $iconstyle)
##################################################################################
sub kml_placemark {

        my ($name, $lat, $lon, $elev, $desc, $iconstyle, $vis, $alt, $range, $tilt, $heading, $altmode) = @_;
        my $str = "<Placemark>\n";
        $str .= "\t<name>$name</name>\n";
	$str .= "\t<visibility>$vis</visibility>\n";
	$str .= "\t<LookAt><longitude>$lon</longitude><latitude>$lat</latitude><altitude>$alt</altitude><range>$range</range><tilt>$tilt</tilt><heading>$heading</heading></LookAt>\n";
        $str .= "\t<styleUrl>#$iconstyle</styleUrl>\n" if $iconstyle;
        $str .= "\t<description>$desc</description>\n";
        $str .= "\t<Point><coordinates>$lon,$lat,$elev</coordinates><altitudeMode>$altmode</altitudeMode></Point>\n";
        $str .= "</Placemark>\n";
        return $str;
}

#################################
### KML FOOTER
###
### $str = &kml_footer();
#################################
sub kml_footer {
        return "</kml>\n";
}
####################################################
### KML LINESTRING
###
### $str = &kml_linestring($label, $linestyle, @vertices)
######################################################
sub kml_linestring {
        my ($label, $linestyle, @vertices) = @_;
        my $str = "<Placemark>\n";
        $str .= "\t<name>$label</name>\n";

        $str .= "\t<styleUrl>$linestyle</styleUrl>\n";
        $str .= "\t<LineString>\n";
        $str .= "\t\t<extrude>0</extrude>\n";
        $str .= "\t\t<tessellate>1</tessellate>\n";
        $str .= "\t\t<altitudeMode>clampToGround</altitudeMode>\n";
        $str .= "\t\t<coordinates>\n";
        foreach my $vertex (@vertices) {
                $str .= "\t\t\t$$vertex{'lon'},$$vertex{'lat'}\n";
        }
        # Add the first vertex again to complete closed loop
        my $vertex = $vertices[0];
        $str .= "\t\t\t$$vertex{'lon'},$$vertex{'lat'}\n";
        $str .= "\t\t</coordinates>\n";
        $str .= "\t</LineString>\n";
        $str .= "</Placemark>\n";
        return $str;
}

######################################################
### KML POLYGON
###
### $str = &kml_polygon($label, $polystyle, @vertices)
######################################################

sub kml_polygon {
        my ($label, $polystyle, @vertices) = @_;
        my $str = "<Placemark>\n";
        $str .= "\t<name>$label</name>\n";
        $str .= "\t<styleUrl>$polystyle</styleUrl>\n";
        $str .= "\t<Polygon>\n";
        $str .= "\t\t<extrude>0</extrude>\n";
        $str .= "\t\t<tessellate>1</tessellate>\n";
        $str .= "\t\t<altitudeMode>clampToGround</altitudeMode>\n";
        $str .= "\t\t<outerBoundaryIs>\n";
        $str .= "\t\t<LinearRing>\n";
        $str .= "\t\t<coordinates>\n";
        foreach my $vertex (@vertices) {
                $str .= "\t\t\t$$vertex{'lon'},$$vertex{'lat'}\n";
        }
        $str .= "\t\t</coordinates>\n";
        $str .= "\t\t</LinearRing>\n";
        $str .= "\t\t</outerBoundaryIs>\n";
        $str .= "\t</Polygon>\n";
        $str .= "</Placemark>\n";
        return $str;
}
##########################################################################
### NEAREST_STATIONS
###
### $success = &nearest_stations($stationdb, $olat, $olon, $km, $stationref)
###
### Search stationdb and find all stations within km of olon,olat
### Populates a station ref, which is an array of hash references
### Each station hash has keys sta, chan, snet, lon, lat, elev, dist
###########################################################################
sub nearest_stations {
        my ($stationdb, $olat, $olon, $range, $stationref) = @_;
        my @stations = [];
        my $stationnum = -1;
        my @db = dbopen_table("$stationdb.site", "r");
        @db = dbsubset(@db, "offdate == NULL");
        @db = dbsubset(@db, "deg2km(distance($olat, $olon, lat, lon)) < $range");

        my $nstations = dbquery(@db, "dbRECORD_COUNT");
	print "Got $nstations stations within $range km\n";
        my @db2 = dbopen_table("$stationdb.sitechan", "r");
        @db = dbjoin(@db, @db2);
        @db = dbsubset(@db, "chan =~ /[BES]HZ.*/");
        @db2 = dbopen_table("$stationdb.snetsta", "r");
        @db = dbjoin(@db, @db2);

        $nstations = dbquery(@db, "dbRECORD_COUNT");
        my $laststa = "DUMM";
        for (my $j=0; $j < $nstations; $j++) {
                $db[3] = $j;
                my ($sta, $lat, $lon, $elev, $snet, $chan) = dbgetv(@db, "sta", "lat", "lon", "elev", "snet", "chan");
                if ($laststa ne $sta) {
			print "nearest_stations: $sta $chan $snet\n";
                        my $dist = sprintf("%.1f", dbex_eval(@db2, "deg2km(distance($olat, $olon, $lat, $lon))") ) ;

                        #my %station = { "sta" => $sta, "chan" => $chan, "snet" => $snet, "lat" => $lat, "lon" => $lon, "elev" => $elev, "dist" => $dist };
                        my %station = {};
                        $station{"sta"} = $sta;
                        $station{"chan"} = $chan;
                        $station{"snet"} = $snet;
                        $station{"lat"} = $lat;
                        $station{"lon"} = $lon;
                        $station{"elev"} = $elev;
                        $station{"dist"} = $dist;
                        $stations[++$stationnum] = \%station;
			#prettyprint(\%station);
                }
                $laststa = $sta;
        }

        @$stationref = @stations;
        dbclose(@db);
        #dbclose(@db2);
        return 1;
}
###############################################################
### GET_REGION
###
### $success = &get_region($regiondb, $regname, \%vertices);
###############################################################
sub get_region {
        my ($regiondb, $regname, $verticesref) = @_;
        my @db = dbopen_table("$regiondb.regions", "r") or die("Cannot open $regiondb.regions\n");
        @db = dbsubset(@db, "regname == \"$regname\"");
        my $found = 0;
        my $nvertices = dbquery(@db, "dbRECORD_COUNT");
        my @vertexlist = [];
        if ($nvertices>2) {
                for (my $k = 0; $k < 4; $k++) {
                        $db[3] = $k;
                        my ($lat, $lon) = dbgetv(@db, 'lat', 'lon');
                        my $vertexref = {lat => $lat, lon => $lon};
                        $vertexlist[$k] = $vertexref;
                }
                $found = 1;
        }
        dbclose(@db);
        @$verticesref = @vertexlist;
        return 1;
}

##############################################################
### GETVOLCANOPLACES
###
### $success = &getvolcanoplaces($placesdb, \%volcanoes);
#############################################################
sub getvolcanoplaces {
        my ($volcanodb, $volcanoesref) = @_;
        my @volcanolist = [];
        my @db = dbopen_table("$volcanodb.places", "r");
        @db = dbsort(@db, '-r', 'lon');
        my $nvolcanoes = dbquery(@db, "dbRECORD_COUNT");
        for (my $i=0; $i<$nvolcanoes; $i++) {
                $db[3] = $i;
                # a kludge, we know 4 volcanoes are left of international date line
                my $index = $i - 4;
                $index += $nvolcanoes if ($index < 0);
                my ($name, $lat, $lon) = dbgetv(@db, "place", "lat", "lon");
                my $elev = 0;
                my $volcanoref = {name => $name, lat => $lat, lon => $lon, elev => $elev};
                $volcanolist[$index] = $volcanoref;
                #print "get_volcanoes: ",$$volcanoref{'name'}, $$volcanoref{'lat'}, $$volcanoref{'lon'}, ": \n";
        }
        @$volcanoesref = @volcanolist;
        dbclose(@db);
        return 1;
}

sub get_legend {                ##### write out a network link to a color and size legend
	my $str=<<"EOF";
        <ScreenOverlay>
        <name>Legend</name>
        <Icon>
        <href>http://www.avo.alaska.edu/eq/kml/icons/depth_mag_scale.png</href>
        </Icon>
        <overlayXY x="0" y="1" xunits="fraction" yunits="fraction"/>
        <screenXY x="0.01" y="8" xunits="fraction" yunits="insetPixels"/>
        <rotationXY x="0.5" y="0.5" xunits="fraction" yunits="fraction"/>
        <size x="0" y="0" xunits="pixels" yunits="pixels"/>
        </ScreenOverlay>
EOF
	return $str;
}
