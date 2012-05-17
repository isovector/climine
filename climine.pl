#!/usr/bin/perl

### EDIT THESE IF YOU DON'T WANT TO ENTER THEM AS FLAGS ###
my $opt_user        = "";
my $opt_pwd         = "";

###########################################################
# CLImine - a CLI query client for jobmine                #
#    written by Sandy Maguire (amaguire@uwaterloo.ca)     #
#                                                         #
# Last revised 2012-05-17                                 #
#                                                         #
# This software is licensed under the GPLv2               #
# http://www.gnu.org/licenses/old-licenses/gpl-2.0.html   #
###########################################################

use Getopt::Long qw(:config bundling);

# options
my $opt_verbose     = 0;
my $opt_color       = -1;
my $opt_pending     = -1;
my $opt_screened    = -1;
my $opt_alternate   = -1;
my $opt_selected    = -1;
my $opt_totals      = 0;
my $opt_wait        = 0;
my $opt_help        = 0;
my $opt_none        = 0;
my $opt_job         = "NO_JOB_TITLE";
my $opt_employer    = "NO_EMPLOYER_NAME";
my $opt_jobid       = "########";
our $opt_debug      = 0;

GetOptions (
    'user=s'    => \$opt_user,
    'pass=s'    => \$opt_pwd,
    'verbose!'  => \$opt_verbose,
    'color!'     => \$opt_color,
    'pending!'  => \$opt_pending,
    'screened!' => \$opt_screened,
    'alternate!'=> \$opt_alternate,
    'selected!' => \$opt_selected,
    'id=s'      => \$opt_jobid,
    'job=s'     => \$opt_job,
    'employer=s'=> \$opt_employer,
    'totals!'   => \$opt_totals,
    'less'      => \$opt_wait,
    'just'      => \$opt_none,
    'help'      => \$opt_help,
    'debug'     => \$opt_debug
);

# boring help display
if ($opt_help) {
    print "Usage: climine.pl [--help] [--verbose] [--[no]color] [--less] [--totals] [--debug] [<options>]\n";
    print "  options:\n";
    print "  --user=<str>\t\tlogin as user <str>\n";
    print "  --pass=<str>\t\tlogin with password <str>\n";
    print "  --just\t\tonly show explicitly set jobs, default is all jobs\n";
    print "  --[no]pending\t\t[don't] show 'Applied' jobs\n";
    print "  --[no]screened\t[don't] show 'Not Selected' jobs\n";
    print "  --[no]alternate\t[don't] show 'Alternate' jobs\n";
    print "  --[no]selected\t[don't] show 'Selected' jobs\n";
    print "  --job=<str>\t\tsearch for <str> in job titles\n";
    print "  --employer=<str>\tsearch for <str> in employer names\n";
    print "  --id=<int>[,...]\tsearch for job(s) with id(s) <int>\n";
    exit;
}

$opt_jobid =~ s/,/|/g;

# if --just is set, show only those that are requested
if ($opt_none) {
    $opt_pending = 0    if $opt_pending == -1;
    $opt_screened = 0   if $opt_screened == -1;
    $opt_alternate = 0  if $opt_alternate == -1;
    $opt_selected = 0   if $opt_selected == -1;
}

# no username/password
if ($opt_user eq "" || $opt_pwd eq "") {
    print "Error: no username and/or password specified\n";
    print "You must either specify defaults by editing climine.pl,\n";
    print "or set these options with the --user and --pass flags.\n";
    exit;
}

use LWP;
use LWP::UserAgent;
use HTTP::Request::Common qw(POST);
use HTML::Form;
use HTML::Parser;

my %totals = (
        "Applied"       => 0,
        "Not Selected"  => 0,
        "Alternate"     => 0,
        "Selected"      => 0
    );

package IdentityParse;
use base HTML::Parser;
our %jobs;
our $jobid = "", $started, $valid, $parsing, $count = 0;

sub trim($) {
	my $string = shift;
	$string =~ s/^\s+//;
	$string =~ s/\s+$//;

    return "" if $string eq "&nbsp;" || $string eq "Edit Application" || $string eq "View Package";
	return $string;
}

sub isnumeric($) {
    my $string = shift;
    return $string =~ m/^[0-9]+$/;
}

sub start {
    my ($self, $tag, $attr, $attreseq, $origtext) = @_;
    my %attr = @_[2];
    my @attreseq = @_[3];

    $valid = false;

    # there are 2 tables like this, we want the last one
    if ($tag eq "table" && $attr->{dir} eq "ltr" && $attr->{class} eq "PSLEVEL1GRID") {
        $parsing = true if ++$count == 2;
    } elsif ($tag eq "td") {
        # the job id has a height of 17
        $started = true if $attr->{height} == 17;

        # relevant cells have class PSLEVEL1GRIDODDROW, for some reason...
        $valid = true if $attr->{class} eq "PSLEVEL1GRIDODDROW";
        
    } elsif ($tag eq "tr") {
        print "Ending job $jobid\n" if $opt_debug;

        # this jobid is no longer relevant
        $jobid = "";
    }
}

sub end {
    my ($self, $tag, $origtext) = @_;

    # print a final debug \n
    print "\n" if $tag eq "html" && $opt_debug;
}

sub text {
    my ($self, $text) = @_;
    
    $text = trim $text;
    
    # we have no interest in null cells!
    return if $text eq "";

    if ($valid) {
        # we need a new jobid
        if ($started && $jobid eq "" && $parsing) {
            if (isnumeric($text)) {
                $jobid = $text;
                $jobs{$jobid} = $text;
                $jobs{$jobid}[0] = $text;
                $started = false;
                print "Setting job to $jobid\n" if $opt_debug;
            }
        }

        # we are in job parsing mode
        elsif (!($jobid eq ""))  {
            push @{$jobs{$jobid}}, $text;
            print "Pushing $text into $jobid\n" if $opt_debug;
        }
    }
}

# check for color support
my $hasColor = eval { require Term::ExtendedColor; };
if (!$hasColor && $opt_color == 1) {
    print "Warning: The --color flag requires Term::ExtendedColor which is not installed\n";
    $opt_color = 0;
} elsif ($opt_color == -1) {
    # we default to --color if you have it
    $opt_color = $hasColor ? 1 : 0;
}

# check for wait support
my $hasWait  = eval { require Term::ReadKey; };
if (!$hasWait && $opt_wait) {
    print "Warning: The --wait flag requires Term::ReadKey which is not installed\n";
    $opt_wait = 0;
}

print "Requesting login form\n" if $opt_verbose;

# build the user agent
my $ua = LWP::UserAgent->new();
$ua->agent('Mozilla/5.0');
$ua->cookie_jar({ file => "$ENV{HOME}/.cookies.txt" });

# get the page, and then the login form
my $req   = HTTP::Request->new(GET => 'https://jobmine.ccol.uwaterloo.ca/psp/SS/?cmd=login');
my $res   = $ua->request($ua->prepare_request($req));
my @forms = HTML::Form->parse($res);
my $form  = $forms[1];

print "Logging in as $opt_user...\n" if $opt_verbose;

# login
$form->value('userid', $opt_user);
$form->value('pwd', $opt_pwd);
my $freq = $form->click;
$freq = $ua->prepare_request($freq);
my $fres = $ua->request($freq);

#die "Unable to login: Jobmine is offline\n"                     if $fres->as_string =~ m/302 Moved Temporarily/;
die "Unable to login: Invalid username and/or password\n"       if $fres->as_string =~ m/errorCode=105/;
print "Logged in successfully\nGetting application list...\n"   if $opt_verbose;

# redirect to the applications page
$req = HTTP::Request->new(
    GET => 'https://jobmine.ccol.uwaterloo.ca/psc/SS/EMPLOYEE/WORK/c/UW_CO_STUDENTS.UW_CO_APP_SUMMARY.GBL?pslnkid=UW_CO_APP_SUMMARY_LINK&FolderPath=PORTAL_ROOT_OBJECT.UW_CO_APP_SUMMARY_LINK&IsFolder=false&IgnoreParamTempl=FolderPath%2cIsFolder&PortalActualURL=https%3a%2f%2fjobmine.ccol.uwaterloo.ca%2fpsc%2fSS%2fEMPLOYEE%2fWORK%2fc%2fUW_CO_STUDENTS.UW_CO_APP_SUMMARY.GBL%3fpslnkid%3dUW_CO_APP_SUMMARY_LINK&PortalContentURL=https%3a%2f%2fjobmine.ccol.uwaterloo.ca%2fpsc%2fSS%2fEMPLOYEE%2fWORK%2fc%2fUW_CO_STUDENTS.UW_CO_APP_SUMMARY.GBL%3fpslnkid%3dUW_CO_APP_SUMMARY_LINK&PortalContentProvider=WORK&PortalCRefLabel=Applications&PortalRegistryName=EMPLOYEE&PortalServletURI=https%3a%2f%2fjobmine.ccol.uwaterloo.ca%2fpsp%2fSS%2f&PortalURI=https%3a%2f%2fjobmine.ccol.uwaterloo.ca%2fpsc%2fSS%2f&PortalHostNode=WORK&NoCrumbs=yes&PortalKeyStruct=yes'
);
$res = $ua->request($req);

print "Parsing html...\n\n" if $opt_verbose;

# scrape out our information
my $parser = new IdentityParse;
$parser->case_sensitive(false);
$parser->parse($res->as_string);

# no string echo if we're in --less mode
Term::ReadKey::ReadMode(2) if $opt_wait;

# now let's sort everything
my @selected;
my @alternate;
my @applied;
my @notselect;
my @merged;
while (($key, $val) = each(%jobs)) {
    my @array = @{$val};
    my $status = $#array == 8 ? $array[6] : $array[5];

    $status = trim $status;
    $totals{$status}++ if defined $totals{$status};

    push @selected,  \@array 
        if $status eq "Selected" && ($opt_selected || 
            $array[1] =~ m/$opt_job/i || 
            $array[2] =~ m/$opt_employer/i ||
            $array[0] =~ m/$opt_jobid/);
    push @alternate, \@array 
        if $status eq "Alternate" && ($opt_alternate || 
            $array[1] =~ m/$opt_job/i || 
            $array[2] =~ m/$opt_employer/i ||
            $array[0] =~ m/$opt_jobid/);
    push @applied,   \@array 
        if $status eq "Applied" && ($opt_pending || 
            $array[1] =~ m/$opt_job/i || 
            $array[2] =~ m/$opt_employer/i ||
            $array[0] =~ m/$opt_jobid/);
    push @notselect, \@array 
        if $status eq "Not Selected" && ($opt_screened || 
            $array[1] =~ m/$opt_job/i || 
            $array[2] =~ m/$opt_employer/i ||
            $array[0] =~ m/$opt_jobid/);
}

# merge them back
for my $val (@selected)  { push @merged, $val; }
for my $val (@alternate) { push @merged, $val; }
for my $val (@notselect) { push @merged, $val; }
for my $val (@applied)   { push @merged, $val; }

my $output = 0;
for my $val (@merged) {
    my @array = @{$val};
    my $status = $#array == 8 ? $array[6] : $array[5];

    $status = trim $status;

    if (!$output) {
        $output = 1;
        print "Listings:" if $opt_verbose;
    }

    my $jobid = $array[0];

    # color it if we can :)
    if ($opt_color) {
        $jobid  = Term::ExtendedColor::fg('yellow16', $jobid);
        $status = Term::ExtendedColor::fg('gray20', $status)    if $status eq "Applied";
        $status = Term::ExtendedColor::fg('magenta23', $status) if $status eq "Alternate";
        $status = Term::ExtendedColor::fg('bold', Term::ExtendedColor::fg('red2', $status))       if $status eq "Not Selected";
        $status = Term::ExtendedColor::fg('bold', Term::ExtendedColor::fg('magenta23', $status))  if $status eq "Selected";
    }

    # print her out!
    print "\n#$jobid: $status\n";
    print "Job Title: $array[1]\n";
    print "Employer : $array[2]\n";

    Term::ReadKey::ReadKey(0) if $opt_wait;
} 

Term::ReadKey::ReadMode(0) if $opt_wait;

# here are our totals
if ($opt_totals) {
    print "\n------------------------------\n\n" if $output;

    print Term::ExtendedColor::fg('bold', "Totals:\n") if $opt_color;
    print "Totals:\n"                              unless $opt_color;
    print "$key: $val\n" while ($key, $val) = each(%totals);
}
