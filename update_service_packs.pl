#!/usr/bin/perl -w
# print "Start\n";
use warnings;
use strict;
$| = 1; 
$SIG{__WARN__} = sub { die @_ };

use Cwd 'abs_path','chdir';
use File::Basename;

BEGIN {
    my $path_prefix = (fileparse(abs_path($0), qr/\.[^.]*/))[1]."";
    my $need= "$path_prefix/instantclient_11_2/";
    my $ld= $ENV{LD_LIBRARY_PATH};
    if(  ! $ld  ) {
        $ENV{LD_LIBRARY_PATH}= $need;
    } elsif(  $ld !~ m#(^|:)\Q$need\E(:|$)#  ) {
        $ENV{LD_LIBRARY_PATH} .= ':' . $need;
    } else {
        $need= "";
    }
    if(  $need  ) {
        exec 'env', $^X, $0, @ARGV;
    }
}

use lib (fileparse(abs_path($0), qr/\.[^.]*/))[1]."our_perl_lib/lib";
use DBI;
use Data::Dumper;
$Data::Dumper::Sortkeys = 1;

my $path_prefix = (fileparse(abs_path($0), qr/\.[^.]*/))[1]."";
use Log::Log4perl qw(:easy);
Log::Log4perl->init("$path_prefix/log4perl.config");
sub logfile {
  return "/var/log/mind/wiki_logs/wiki_update_servicepacks";
}

use Mind_work::WikiCommons;
use Mind_work::WikiWork;

our $dbh;
our $work_type = shift;
my $urlsep = WikiCommons::get_urlsep;
# my $our_wiki = WikiWork->new('robot', '1');
my $our_wiki = WikiWork->new();
my $deployment_ns = "SC_Deployment";
my $canceled_ns = "SC_Canceled";
my $deployment_wiki = getWikiPages($deployment_ns);
clean_existing_deployment($deployment_wiki) if defined $work_type && $work_type eq "d";
my $cancel_wiki = getWikiPages($canceled_ns);
my @arr1 = (keys %$deployment_wiki);
my @arr2 = (keys %$cancel_wiki);
my ($only_in_arr1, $only_in_arr2, $intersection) = WikiCommons::array_diff(\@arr1, \@arr2);
delete $deployment_wiki->{$_} foreach (@$intersection);

sub clean_existing_deployment {
    my $pages = shift;
    foreach my $page (sort keys %$pages){
	next if $page =~m/^[a-z][0-9]+$/i;
	$our_wiki->wiki_delete_page("$deployment_ns:$page");
    }
    exit 0;
}

sub sql_connect {
    my ($ip, $sid, $user, $pass) = @_;
    $dbh=DBI->connect("dbi:Oracle:host=$ip;sid=$sid", "$user", "$pass")|| die( $DBI::errstr . "\n" );
    $dbh->{AutoCommit}    = 0;
    $dbh->{RaiseError}    = 1;
    $dbh->{ora_check_sql} = 0;
    $dbh->{RowCacheSize}  = 16;
    $dbh->{LongReadLen}   = 52428800;
    $dbh->{LongTruncOk}   = 0;
}

sub getSPs {
    my $SEL_INFO = "
select a.id,
       c.projectname,
       b.productname,
       a.version,
       a.service_pack,
       a.build_type,
       nvl(a.description, ' ') description,
       nvl(a.actual_build_date, '31dec2050')
  from SC_BUILD_MANAGER a, scprods b, SCPROJECTS c
 where (actual_build_date >= '1jan2010' or actual_build_date is null)
   and b.productid = a.product
   and a.projectcode = c.projectcode";
    my $info;
    my $sth = $dbh->prepare($SEL_INFO);
    $sth->execute();
    while ( my @row=$sth->fetchrow_array() ) {
# 	push @$info, \@row;
	$info->{"$row[1]$urlsep$row[2]$urlsep$row[3]"}->{$row[0]}->{'sp'} = $row[4];
	$info->{"$row[1]$urlsep$row[2]$urlsep$row[3]"}->{$row[0]}->{'version'} = $row[3];
	$info->{"$row[1]$urlsep$row[2]$urlsep$row[3]"}->{$row[0]}->{'build_type'} = $row[5];
	$info->{"$row[1]$urlsep$row[2]$urlsep$row[3]"}->{$row[0]}->{'description'} = $row[6];
	$info->{"$row[1]$urlsep$row[2]$urlsep$row[3]"}->{$row[0]}->{'build_date'} = $row[7];
	$info->{"$row[1]$urlsep$row[2]$urlsep$row[3]"}->{"XXX_Cat"} = "$row[1]$urlsep$row[2]";
    }
    return $info;
}

sub getTasks_inSP {
    my $sp = shift;
    my $SEL_INFO = "
SELECT T1.CHANGEID,
       nvl(c.name, ' '),
       nvl(T1.PRIORITY, ' '),
       T1.ChangeType,
       T1.STATUS,
       T1.TITLE,
       nvl(T1.COMMENTS,' '),
       i.WorkerName,
       nvl(t1.modules, ' ')
  FROM SCChange T1, SC_PLANS p, SC_BUILD_MANAGER b, SCWork i, sccustomers c
 WHERE  T1.Product IS NOT NULL
   AND T1.customer_id = c.id(+)
   AND T1.ChangeId = p.CHANGE_ID
   AND b.ID(+) = p.BUILD_ID
   AND to_number(T1.Initiator) = i.ID(+)
   AND p.build_id = :SP_ID";
    my $info;
    my $sth = $dbh->prepare($SEL_INFO);
    $sth->bind_param( ":SP_ID", $sp );
    $sth->execute();
    while ( my @row=$sth->fetchrow_array() ) {
# 	push @$info, \@row;
	$info->{$row[0]}->{'CUSTOMER'} = $row[1];
	$info->{$row[0]}->{'PRIORITY'} = $row[2];
	$info->{$row[0]}->{'ChangeType'} = $row[3];
	$info->{$row[0]}->{'STATUS'} = $row[4];
	$info->{$row[0]}->{'TITLE'} = $row[5];
	$info->{$row[0]}->{'COMMENTS'} = $row[6];
	$info->{$row[0]}->{'WorkerName'} = $row[7];
	$info->{$row[0]}->{'modules'} = $row[8];
    }
    return $info;
}

sub getClones {
    my $change_id = shift;
    my $SEL_INFO = "
select a.changeid, a.parent_change_id, b.description
  from scchange a, sc_categories b
 where changetype = 'Change'
   and parent_change_id <> changeid
   and b.id = category_id
   and b.clone = 'Y'
   and changeid = :CHANGE_ID";
    my $info;
    my $sth = $dbh->prepare($SEL_INFO);
    while ($change_id ne "") {
	$sth->bind_param( ":CHANGE_ID", $change_id );
	$sth->execute();
	$change_id = "";
	while ( my @row=$sth->fetchrow_array() ) {
	    $change_id = $row[1];
	    last;
	}
	push @$info, $change_id if $change_id ne "";
    }
    return $info;
}

sub getProjects {
    my $SEL_INFO = "
select c.projectname, b.productname
  from scprods b, SCPROJECTS c
 where b.projectcode = c.projectcode
 order by projectname, productname";
    my $info;
    my $sth = $dbh->prepare($SEL_INFO);
    $sth->execute();
    while ( my @row=$sth->fetchrow_array() ) {
	push @$info, \@row;
    }
    return $info;
}

sub sql_get_modules {
    my @ids = @_;
    chomp @ids;
    my @numbers;
    for (my $i=0;$i<=$#ids;$i++) {
	$ids[$i] =~ s/\s*//g;
	push @numbers, '\''.$ids[$i].'\'' if ($ids[$i]);
    }
    my $tmp = join ',', @numbers;
    return \@numbers if (@numbers == 0);
    my $SEL_MODULES = "select description from sc_modules where id in ( $tmp )";
    my $sth = $dbh->prepare($SEL_MODULES);
    $sth->execute();
    my @modules = ();
    while ( my @row=$sth->fetchrow_array() ) {
	push @modules, @row;
    }
    return \@modules;
}

sub getWikiPages {
    my $ns = shift;
    my $pages;
    my $info;
    $ns =~ s/_/ /g;
    my $namespaces = $our_wiki->wiki_get_namespaces;
    foreach (sort keys %$namespaces){
	next if $namespaces->{$_} ne $ns;
	$pages = $our_wiki->wiki_get_all_pages($_);
    }
    foreach my $name (@$pages) {
	$name =~ s/^$ns://;
	$info->{$name} = "$ns:$name"
    }
    return $info;
}

sub makeDeploymentPage {
    my $ids = shift;
    my $title = $ids->{'page'};
#     delete $ids->{'page'};
    my $clones;
    my $uniq_ids;
    foreach (sort keys %$ids) {
	next if $_ eq "page";
	$uniq_ids->{$_} = 1 if defined $deployment_wiki->{$_};
	if (defined $ids->{$_}) {
	    $clones .= "\n\n$_ -> ". join " -> ",  @{$ids->{$_}};
	    foreach my $clone (@{$ids->{$_}}) {
		$uniq_ids->{$clone} = 1 if defined $deployment_wiki->{$clone};
	    }
	}
    }
    return if ! defined $uniq_ids;
    $clones =~ s/([a-z][0-9]+)/[[SC:$1|$1]]/gmsi if defined $clones;
    my $txt;
    foreach (sort keys %$uniq_ids) {
	$txt .= "\n\n\n\n{{:".$deployment_wiki->{$_}."}}" if defined $deployment_wiki->{$_};
    }
    $txt .= "\n\n\n\n----\n----\n\nThe following clones where found for this SP:$clones" if defined $clones;
    $our_wiki->wiki_edit_page($title, $txt) if defined $uniq_ids;
}

$ENV{NLS_LANG} = 'AMERICAN_AMERICA.AL32UTF8';
sql_connect('10.0.0.103', 'SCROM', 'scview', 'scview');
my $projects_title = "Software products";
my $projs = getProjects;
foreach (@$projs) {
    my @tmp = @$_;
    $our_wiki->wiki_edit_page("Category:$tmp[0]$urlsep$tmp[1]", "----\n[[Category:$projects_title]]");
}

INFO "Get all service packs.\n";
my $sps = getSPs;

foreach my $sp (sort keys %$sps) {
# next if $sp !~ m/iPhonEX -- iPhonEX -- 7.00.002/i;
# next if $sp !~ m/Sentori -- Main/i;
    my $sp_ids = $sps->{$sp};
    my $full_deployment->{'page'} = "$deployment_ns:Deployment$urlsep$sp$urlsep"."full";
    my $end = "[[Category:".$sps->{$sp}->{'XXX_Cat'}."]]";
    my $txt = "[[".$full_deployment->{'page'}."| Full deployment consideration]].\n\n\n";
    my $txt_all = {};
    delete $sps->{$sp}->{'XXX_Cat'};
    foreach my $id (sort keys %$sp_ids) {
	my $sp_txt;
	my $sp_deployment->{'page'} = "$deployment_ns:Deployment$urlsep$sp$urlsep".$sp_ids->{$id}->{'sp'};
	my $sp_bugs->{'page'} = "$deployment_ns:Bugs$urlsep$sp$urlsep".$sp_ids->{$id}->{'sp'};
	$txt_all->{$sp_ids->{$id}->{'sp'}} = "\n\n{{:".$sp_bugs->{'page'}."}}";
	$sp_txt .=
'{| class="wikitable" style="background: #f5fffa"
|- style="background: #DDFFDD;"
! style="background: #cef2e0;" | ID
! style="background: #cef2e0;" | Type
! style="background: #cef2e0;" | Title
! style="background: #cef2e0;" | Affected
! style="background: #cef2e0;" | Customer
! style="background: #cef2e0;" | Status
! style="background: #cef2e0;" | Comments
! style="background: #cef2e0;" | Priority
! style="background: #cef2e0;" | Worker Name
';
	my $tasks = getTasks_inSP($id);
	foreach my $sc (sort keys %$tasks) {
	    WikiCommons::set_real_path((fileparse(abs_path($0), qr/\.[^.]*/))[1]."");
	    my $cust = WikiCommons::get_correct_customer($tasks->{$sc}->{'CUSTOMER'});
	    if (defined $cust && $cust !~ m/^\s*$/) {
		$cust = "[[:Category:$cust|$cust]]";
	    } else {
		$cust = $tasks->{$sc}->{'CUSTOMER'} ;
	    }
# print "$sp_deployment->{'page'}\n";
# print Dumper($id, $tasks->{$sc}) if ! defined $tasks->{$sc}->{'modules'};
	    my @module_ids = split ",",$tasks->{$sc}->{'modules'};
	    my $modules = sql_get_modules(@module_ids);
	    my $modules_str = join "\' <br/> \'", @$modules;

	    LOGDIE Dumper($sc, $tasks->{$sc}->{'ChangeType'}, $tasks->{$sc}->{'TITLE'}, $modules_str, $cust, $tasks->{$sc}->{'STATUS'}, $tasks->{$sc}->{'COMMENTS'}, $tasks->{$sc}->{'PRIORITY'}, $tasks->{$sc}->{'WorkerName'}) if ! defined $sc || ! defined $tasks->{$sc}->{'ChangeType'} || ! defined $tasks->{$sc}->{'TITLE'} || ! defined $modules_str || ! defined $cust || ! defined $tasks->{$sc}->{'STATUS'} || ! defined $tasks->{$sc}->{'COMMENTS'} || ! defined $tasks->{$sc}->{'PRIORITY'} || ! defined $tasks->{$sc}->{'WorkerName'};
	    $sp_txt .= "|-
| [[SC:$sc|$sc]] || ".$tasks->{$sc}->{'ChangeType'}." || ".$tasks->{$sc}->{'TITLE'}." || \'$modules_str\' "." || $cust || ".$tasks->{$sc}->{'STATUS'}." || ".$tasks->{$sc}->{'COMMENTS'}." || ".$tasks->{$sc}->{'PRIORITY'}." || ".$tasks->{$sc}->{'WorkerName'}."\n";
	    $full_deployment->{$sc} = getClones($sc);
	    $sp_deployment->{$sc} = getClones($sc);
	}
	$sp_txt .= "|}\n\n";
	makeDeploymentPage($sp_deployment);
	$sp_txt = "[[".$sp_deployment->{'page'}."|Deployment consideration]].\n\n$sp_txt" if $our_wiki->wiki_exists_page($sp_deployment->{'page'});
	$sp_txt = "\n----\n".$sp_ids->{$id}->{'build_type'}." ".$sp_ids->{$id}->{'version'}." ".$sp_ids->{$id}->{'sp'}.". Description: ".$sp_ids->{$id}->{'description'}.". Build date: ".$sp_ids->{$id}->{'build_date'}."\n\n$sp_txt";
	$our_wiki->wiki_edit_page($sp_bugs->{'page'}, $sp_txt);
	undef $sp_deployment;
    }
    makeDeploymentPage($full_deployment);
    $txt .= $txt_all->{$_} foreach (reverse sort keys %$txt_all);
    $txt .= "$end\n\n";
    $our_wiki->wiki_edit_page("$deployment_ns:$sp", $txt);
}
$dbh->disconnect if defined($dbh);
INFO "Done.\n";
