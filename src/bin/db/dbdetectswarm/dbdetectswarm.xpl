
##############################################################################
# Author: Glenn Thompson (GT) 2009
#         ALASKA VOLCANO OBSERVATORY
#
# History:
#	2009-04-17: Created by GT, based on dbswarmdetect, a static threshold swarm detection module
#	
# To do:
#	* Modify to work with a parameter file that describes all subnets, and
#		supports overloading of generic parameters.
#	* Write to a swarm database rather than parameter files for tracking
#		swarms. 
#
##############################################################################

use Datascope;
use Getopt::Std;

use strict;
use warnings;

# Get the program name
our $PROG_NAME;
($PROG_NAME = $0) =~ s(.*/)();  # PROG_NAME becomes $0 minus any path

# Usage - command line options and arguments
our ($opt_p, $opt_t, $opt_e, $opt_v, $opt_d, $opt_r); 
if ( ! &getopts('p:t:evdr') || $#ARGV < 3  ) {
    print STDERR <<"EOU" ;

    Usage: $PROG_NAME [-p pffile] [-e] [-t endtime] [-d] [-v] [-r] eventdb alarmdb swarmdb volc_code

    For more information:
	> man $PROG_NAME	 
EOU
    exit 1 ;
}

# End of  GT Antelope Perl header
#################################################################
use Avoseis::SwarmAlarm;

printf("\n**************************************\n\nRunning $PROG_NAME at %s\n\n", epoch2str(now(),"%Y-%m-%d %H:%M:%S")); 

#### COMMAND LINE ARGUMENTS
my ($eventdb, $alarmdb, $swarmdb, $volc_code) = @ARGV;
my ($endTime);


# read parameter file
print "Reading parameter file for $PROG_NAME\n" if $opt_v;
my ($alarmclass, $alarmname, $msgdir, $msgpfdir, $volc_name, $twin, $auth_subset, $reminders_on, $escalation_on, $swarmend_on, $reminder_time, $newalarmref, $significantchangeref, $trackfile) = &getParams($PROG_NAME, $opt_p, $opt_v, $volc_code);


# read end epoch time or set to now
if ($opt_t) {
	$endTime = $opt_t;
}
else
{
	$endTime = &roundtopreviousminute(now(),60);
}

# dereference refs to hash arrays
my %new_alarm = %$newalarmref;
my %significant_change = %$significantchangeref;
my @stations = [];
my $dbgrid = "grids/dbgrid_".$auth_subset;
if (-e "$dbgrid.site") {
	my @dbs = dbopen_table("$dbgrid.site", "r");
	my $numstations = dbquery(@dbs, "dbRECORD_COUNT");
	if ($numstations > 0) {
		for (my $stanum = 0; $stanum < $numstations; $stanum++) {
			$dbs[3] = $stanum;
			$stations[$stanum] = dbgetv(@dbs, "sta");
		}
	}
	dbclose(@dbs);
}

# GET STATISTICS FOR TIME WINDOW CORRESPONDING TO PREVIOUS MESSAGE CORRESPONDING TO THIS ALARMNAME
# Read swarm_state table
my ($previousLevel) = getSwarmLevel($swarmdb, $alarmname); # return -1 for no rows, 0 for "off", 1 for level 1, 2 for level 2...
my ($previousSwarmIsOver, %current, %prev, $agePreviousMessage);

# START TIME
my $startTime = $endTime - ( 60 * $twin);
printf "Timewindow of $twin minutes from %s to %s\n",epoch2str($startTime, "%Y-%m-%d %H:%M:%S"), epoch2str($endTime, "%Y-%m-%d %H:%M:%S");

# assume there is not an ongoing swarm by default
$previousSwarmIsOver = 1;
$current{'swarm_start'} = -1;
$current{'swarm_end'} = '-1';

# assume prev loaded OK
if ($previousLevel > -1) { 
	%prev = &getLastSwarm($alarmname);

	# display contents
	print "Stats for previous swarm message of alarmname $alarmname\n" if $opt_v;
	prettyprint(\%prev) if $opt_v;

	# IS THAT SWARM STILL CONSIDERED ACTIVE? CHECK ITS swarm_end PARAMETER
	if ( $prev{'swarm_end'} <= 0) {
		$previousSwarmIsOver = 0;
		if ($prev{'swarm_start'} > 0) {
			$current{'swarm_start'} = $prev{'swarm_start'};
		}
	}
	$prevMsgTime = $prev{'timewindow_end'};

	# WHAT IS THE DIFFERENCE BETWEEN TIME NOW AND TIME OF LAST ALARM
	$agePreviousMessage = ($endTime - $prevMsgTime) / 60; # in minutes
	printf "Previous message is %.0f minutes old\n", $agePreviousMessage; 
}
else
{
	$prevMsgTime = 0;
	$alarmkey = 0;
	$agePreviousMessage = 0;
}
print "Previous Swarm Over: $previousSwarmIsOver\n" if $opt_v;


# LOAD EVENT TIMES AND MAGNITUDES
my (@eventTime, @Ml);
printf("Load events from database $eventdb from %s to %s for author $auth_subset\n", epoch2str($startTime, "%Y-%m-%d %H:%M:%S"), epoch2str($endTime, "%Y-%m-%d %H:%M:%S")) if $opt_v;
loadEvents($eventdb, $startTime, $endTime, $auth_subset, \@eventTime, \@Ml, \%current);
printf("Loaded %d events (Ml: @Ml)\n", $#Ml+1);

# GET STATISTICS FOR CURRENT TIME WINDOW
swarmStatistics(\@eventTime, \@Ml, $twin, \%current);
print "\nStats for current time window\n" if $opt_v;
prettyprint(\%current) if $opt_v;

# save to swarmparams db
unless (-e $swarmdb) {
	open(FSP,">$swarmdb");
	print FSP<<"EODES";
#
schema swarmparams
dblocks	local
EODES
	close(FSP);
}
# METRICS TABLE
if ($current{'mean_rate'} > 0) {
	my @dbsp = dbopen_table($swarmdb.".metrics","r+");
	print "Adding row to $swarmdb for $auth_subset\n";
	dbaddv(@dbsp, "auth", $auth_subset, "timewindow_starttime", $startTime, "timewindow_endtime", $endTime, "mean_rate", $current{'mean_rate'}, "median_rate", $current{'median_rate'}, "mean_ml", $current{'mean_ml'}, "cum_ml", $current{'cum_ml'});
	dbclose(@dbsp);
}
########################################################

# CHECK FOR TEST MODE
if ($opt_d) {
	my $str = "test_$PROG_NAME";
	&declareAlarm($str, $str, \%current, $volc_name, $startTime, $endTime, $eventdb, 
                \@stations, $alarmdb, $alarmclass, $alarmkey, $str, $msgdir, $msgpfdir);
	exit;
}

my $alarmSent = 0;

# are we above new swarm alarm threshold?
my $currentLevel = &compareLevels(\%current, \%new_alarm, \%significant_change, $opt_v);

# Any change in level?
if ($currentLevel ne $previousLevel) {

	# New swarm?
	if ($previousLevel < 1) {
		print "THERE IS NO ACTIVE SWARM\nCHECKING FOR NEW SWARM\n";
		# CHECK IF A NEW SWARM HAS BEGUN
		if ($currentLevel > 0) {
			# declare new swarm alarm
			print "Declaring a new alarm\n" if $opt_v;
			$current{'swarm_start'} = $startTime;
			$current{'swarm_end'} = -1;
			&declareAlarm("start", "New Swarm", \%current, $volc_name, $startTime, $endTime, $eventdb, 
	        		\@stations, $alarmdb, $alarmclass, $alarmkey, $alarmname, $msgdir, $msgpfdir);
		}
	}
	else
	{ # swarm is still active, but has it ended, or escalated? or do we need to send a reminder? 
		print "THERE IS AN ACTIVE SWARM\n";
		if ($currentLevel == 0) { # end swarm. 
			# We do not want to declare the swarm as over until at least $twin minutes have passed since start of swarm, otherwise we get too many swarms
			if ( ($endTime - $prev{'swarm_start'}) > (2 * $twin) ) {		
				# DECLARE SWARM OVER
				print "DECLARING SWARM OVER\n";
				$current{'swarm_end'} = $endTime;
				&declareAlarm("end", "Swarm Over", \%current, $volc_name, $startTime, $endTime, $eventdb, 
	                               \@stations, $alarmdb, $alarmclass, $alarmkey, $alarmname, $msgdir, $msgpfdir) if $swarmend_on;
			}
			else
			{
				print "Swarm may have ended, but timeout period not lapsed yet.\n";
			}
		}
		elsif ($currentLevel > $previousLevel)
		{
			print "DECLARING SWARM ESCALATION\n";
			&declareAlarm("escalation", "Swarm Escalation", \%current, $volc_name, $startTime, $endTime, $eventdb, 
	                                            \@stations, $alarmdb, $alarmclass, $alarmkey, $alarmname, $msgdir, $msgpfdir) if $escalation_on;
		}
		else 
		{			
			# CHECK WHETHER TO SEND A REMINDER
			print "SWARM CONTINUING BUT HAS NOT ESCALATED\nCHECKING TO SEE IF IT IS TIME TO SEND A REMINDER\n";

			if ($agePreviousMessage > $reminder_time) {
				# declare swarm reminder warning
				print "DECLARING A REMINDER\n";
				&declareAlarm("reminder", "Swarm Continuing", \%current, $volc_name, $startTime, $endTime, $eventdb, 
	                                                   \@stations, $alarmdb, $alarmclass, $alarmkey, $alarmname, , $msgdir, $msgpfdir) if $reminders_on;
			}
		}

	}


}
# Success
1;
#########################################################

sub declareAlarm {
	my ($msgType, $subject, $currentref, $volc_name, $startTime, $endTime, $eventdb, $stationsref, $alarmdb, $alarmclass, $alarmkey, $alarmname, $msgdir, $msgpfdir) = @_;

	my $endTimeLOCAL  = epoch2str($endTime,'%k:%M:%S %z','US/Alaska');

	# compose Subject
	print "Compose subject\n" if $opt_v;
	$subject = "\'$subject $volc_name $endTimeLOCAL\'";
	
	# composeMessage
	print "Compose message\n" if $opt_v;
	my $txt = &composeMessage($msgType, $currentref,  $startTime, $endTime, $eventdb, $stationsref); 

	# getMessagePath
	print "Get path to write message to\n" if $opt_v;
	my ($mdir, $mdfile) = &getMessagePath($endTime, $msgdir, $alarmname);

	# writeMessage file
	print "Writing message to $mdir/$mdfile\n" if $opt_v;
	&writeMessage($mdir, $mdfile, $txt);

	# addAlarmsRow
	print "Get next alarmid\n" if $opt_v;
	my $alarmid = `dbnextid $alarmdb alarmid`; 
	chomp($alarmid);
	$alarmkey = $alarmid if ($msgType eq "start" || $msgType eq "test");
	print "Writing alarms row\n" if $opt_v;
	my $alarmtime = $startTime;
	$alarmtime = $endTime if ($msgType eq "end");
	&writeAlarmsRow($alarmdb, $alarmid, $alarmkey, $alarmclass, $alarmname, $endTime, $subject, $mdir, $mdfile);

	# getMessagePfPath
	print "Get path to write parameter file to\n" if $opt_v;	
	my ($mpfdir, $mpfdfile) = &getMessagePfPath($endTime, $msgpfdir, $alarmname);

	# addAlarmcacheRow
	print "Writing alarmcache row\n" if $opt_v;
	&writeAlarmcacheRow($alarmdb, $alarmid, $mpfdir, $mpfdfile);

	# putSwarmParams
	print "put swarm parameters to $mpfdir/$mpfdfile\n" if $opt_v;
	$current{'message_type'} = $msgType;
	&putSwarmParams($mpfdir, $mpfdfile, %current);

	# NOW CALL alarm_dispatch TO SEND THE MESSAGE
	#print "call alarmdispatch\n" if $opt_v;
	#&runCommand("dbalarmdispatch -v -p pf/dbalarmdispatch -t $endTime $alarmkey $alarmdb", 1); # alarmdispatch now run whenever alarms table has new row added

}


###############################################################################
### LOAD PARAMETER FILE                                                      ##
### ($alarmclass, $alarmname, $msgdir, $msgpfdir, $volc_name, ...            ##  
###    $volc_code, $twin, $auth_subset, $reminders_on, $escalations_on, ...  ##
###    $cellphones_on, $reminder_time, $newalarmref, ...  ##
###    $significantchangeref) = getParams($PROG_NAME, $opt_p, $opt_v);       ##
###                                                                          ##
### Glenn Thompson, 2009/04/20                                               ##
###                                                                          ##
### Load the parameter file for this program, given it's path                ##
###############################################################################
sub getParams {

	my ($PROG_NAME, $opt_p, $opt_v, $volc_code) = @_;
	my $pfobjectref = &getPf($PROG_NAME, $opt_p, $opt_v);

     
	my ($alarmclass, $alarmname, $msgdir, $msgpfdir, $volc_name, $twin, $auth_subset, $reminders_on, $escalations_on, $swarmend_on, $reminder_time, $newalarmref, $significantchangeref, $trackfile); 

	# Generic parameters
	$alarmclass		= $pfobjectref->{'ALARMCLASS'};
 	$alarmname		= $alarmclass."_".$volc_code;
 	$msgdir			= $pfobjectref->{'MESSAGE_DIR'};
 	$msgpfdir		= $pfobjectref->{'MESSAGE_PFDIR'};
	$volc_name		= "unknown";
	$auth_subset		= $volc_code."_lo";
	$twin			= $pfobjectref->{'TIMEWINDOW'};
	$reminders_on		= $pfobjectref->{'reminders_on'};
	$escalations_on		= $pfobjectref->{'escalations_on'};
	$swarmend_on		= $pfobjectref->{'swarmend_on'};
	$reminder_time		= $pfobjectref->{'REMINDER_TIME'};
	$newalarmref		= $pfobjectref->{'new_alarm'};
	$significantchangeref	= $pfobjectref->{'significant_change'};
	$trackfile		= "state/$alarmname.pf";

	# Now read any subnet specific overrides
	$subnetsref 		= $pfobjectref->{'subnets'};
	$subnetref 		= $subnetsref->{$volc_code};
	if defined($subnetref->{'VOLC_NAME'}) {
        	$volc_name              = $subnetref->{'VOLC_NAME'};
	}
	if defined($subnetref->{'auth_subset'}) {
        	$auth_subset            = $subnetref->{'auth_subset'};
	}
	if defined($subnetref->{'new_alarm'}) {
        	$newalarmref            = $subnetref->{'new_alarm'};
	}
	if defined($subnetref->{'significant_change'}) {
        	$significantchangeref   = $subnetref->{'significant_change'};
	}
	if defined($subnetref->{'trackfile'}) {
        	$trackfile              = $subnetref->{'trackfile'};
	}

	return ($alarmclass, $alarmname, $msgdir, $msgpfdir, $volc_name, $twin, $auth_subset, $reminders_on, $escalations_on, $swarmend_on, $reminder_time, $newalarmref, $significantchangeref, $trackfile); 
}





sub compareLevels {
	my ($dataref, $thresholdref, $opt_v) = @_;
	my %data = %{$dataref};
	my %threshold = %{$thresholdref};

	my $triggered = 0;
	if (   $data{'mean_rate'} >= $threshold{'mean_rate'}  ) {
		$triggered = 1;
	
		# TEST MEDIAN RATE
		if (  defined($significant_change{'median_rate_pcchange'})   ) {
			$triggered = 0 if ($data{'median_rate'} < $threshold{'median_rate'});
		}


		# TEST MEAN ML
		if (defined($significant_change{'mean_ml_change'})) {
			$triggered = 0 if ($data{'mean_ml'} < $threshold{'mean_ml'});
		}

		# TEST CUMULATIVE ML
		if (defined($significant_change{'cum_ml_change'})) {
			$triggered = 0 if ($data{'cum_ml'} < $threshold{'cum_ml'});
		}
		
	}
	return $triggered;
}

sub changeThreshold {
	my ($thresholdref, $significantChangeRef, $epsilon) = @_;
	my %threshold = %{$thresholdref};
	my %significant_change = %{$significantChangeRef};
	my %newthreshold;
	my $fraction;

	# MEAN RATE
	$fraction = sprintf("%.2f",1.0 + $significant_change{'mean_rate_pcchange'}/100.0);
	if ($epsilon == 1) {
		$newthreshold{'mean_rate'} = $threshold{'mean_rate'} * $fraction;
	}
	else
	{
		$newthreshold{'mean_rate'} = $threshold{'mean_rate'} / $fraction;

	}


	# MEDIAN RATE
	if (defined($significant_change{'median_rate_pcchange'})   && defined($threshold{'median_rate'}) ) {
		$fraction = sprintf("%.2f",1.0 + $significant_change{'median_rate_pcchange'}/100.0);
		if ($epsilon == 1) {
			$newthreshold{'median_rate'} = $threshold{'median_rate'} * $fraction;
		}
		else
		{
			$newthreshold{'median_rate'} = $threshold{'median_rate'} / $fraction;
	
		}
	}

	# MEAN ML
	if (defined($significant_change{'mean_ml_change'})   && defined($threshold{'mean_ml'})) {
		$newthreshold{'mean_ml'} = $threshold{'mean_ml'} + $epsilon * $significant_change{'mean_ml_change'};
	}

	# CUMULATIVE ML
	if (defined($significant_change{'cum_ml_change'})  && defined($threshold{'cum_ml'}) ) {
		$newthreshold{'cum_ml'} = $threshold{'cum_ml'}  + $epsilon * $significant_change{'cum_ml_change'};
                if ($@){
                        print "Problem with cumulative ml\n";
                };

	}
	return %newthreshold;
}

sub roundtopreviousminute {
    my ($etime, $interval) = @_;
    my $newetime;
    return $interval * int($etime / $interval);
}
