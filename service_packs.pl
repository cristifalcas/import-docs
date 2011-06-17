#!/usr/bin/perl -w
print "Start\n";
use warnings;
use strict;

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
use Mind_work::WikiCommons;
use Mind_work::WikiWork;

our $dbh;
my $urlsep = WikiCommons::get_urlsep;
my $our_wiki = WikiWork->new('robot', '1');
my $deployment_ns = "SC_Deployment";
my $canceled_ns = "SC_Canceled";
my $deployment_wiki = getWikiPages($deployment_ns);
my $cancel_wiki = getWikiPages($canceled_ns);
my @arr1 = (keys %$deployment_wiki);
my @arr2 = (keys %$cancel_wiki);
my ($only_in_arr1, $only_in_arr2, $intersection) = WikiCommons::array_diff(\@arr1, \@arr2);
delete $deployment_wiki->{$_} foreach (@$intersection);

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
       a.actual_build_date
  from SC_BUILD_MANAGER a, scprods b, SCPROJECTS c
 where actual_build_date >= '1jan2008'
   and b.productid = a.product
   and a.projectcode = c.projectcode
 order by projectname, productname, version desc, service_pack desc";
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
       nvl(T1.CUSTOMER,' '),
       T1.PRIORITY,
       T1.ChangeType,
       T1.STATUS,
       T1.TITLE,
       nvl(T1.COMMENTS,' '),
       i.WorkerName
  FROM SCChange T1, SC_PLANS p, SC_BUILD_MANAGER b, SCWork i
 WHERE  T1.Product IS NOT NULL
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

sub getWikiPages {
    my $ns = shift;
    my $pages;
    my $info;
    $ns =~ s/_/ /g;
    my $namespaces = $our_wiki->wiki_get_namespaces;
    foreach (keys %$namespaces){
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
    delete $ids->{'page'};
    my $clones;
    my $uniq_ids;
    foreach (keys %$ids) {
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
	$txt .= "\n\n{{:".$deployment_wiki->{$_}."}}" if defined $deployment_wiki->{$_};
    }
    $txt .= "\n\n\n\n----\n----\n\nThe following clones where found for this SP:$clones" if defined $clones;
    $our_wiki->wiki_edit_page("$title", "$txt") if defined $uniq_ids;
#     $our_wiki->wiki_delete_page("$title");
#     print Dumper($title, $txt) if defined $uniq_ids;
}

$ENV{NLS_LANG} = 'AMERICAN_AMERICA.AL32UTF8';
sql_connect('10.0.0.103', 'SCROM', 'scview', 'scview');
my $projects_title = "Software products";
my $projs = getProjects;
foreach (@$projs) {
    my @tmp = @$_;
    $our_wiki->wiki_edit_page("Category:$tmp[0]$urlsep$tmp[1]", "----\n[[Category:$projects_title]]");
#     $our_wiki->wiki_delete_page("Category:$tmp[0]$urlsep$tmp[1]");
}

print "Get all service packs.\n";
my $sps = getSPs;
foreach my $sp (sort keys %$sps) {
# next if "$sp" !~ m/iPhonEX -- iPhonEX -- 6.01/i;
# next if "$sp" !~ m/iPhonEX -- iPhonEX -- 7.00.001/i;
    my $sp_ids = $sps->{$sp};
    my $full_deployment->{'page'} = "$deployment_ns:Deployment$urlsep$sp$urlsep"."full";
#     my $category = "\n[[Category:".$sps->{$sp}->{'XXX_Cat'}."]]";
    my $end = "[[Category:".$sps->{$sp}->{'XXX_Cat'}."]]";
    my $txt = "[[".$full_deployment->{'page'}."| Full deployment consideration]].\n\n\n";
    delete $sps->{$sp}->{'XXX_Cat'};
    foreach my $id (reverse sort keys %$sp_ids) {
	my $sp_txt;
	my $sp_deployment->{'page'} = "$deployment_ns:Deployment$urlsep$sp$urlsep".$sp_ids->{$id}->{'sp'};
	my $sp_bugs->{'page'} = "$deployment_ns:Bugs$urlsep$sp$urlsep".$sp_ids->{$id}->{'sp'};
	$txt .= "\n\n{{:".$sp_bugs->{'page'}."}}";
	$sp_txt .= "\n----\n".$sp_ids->{$id}->{'build_type'}." ".$sp_ids->{$id}->{'version'}." ".$sp_ids->{$id}->{'sp'}.". Description: ".$sp_ids->{$id}->{'description'}.". Build date: ".$sp_ids->{$id}->{'build_date'}."\n\n[[".$sp_deployment->{'page'}."|Deployment consideration]].\n\n";
	$sp_txt .=
'{| class="wikitable" style="background: #f5fffa"
|- style="background: #DDFFDD;"
! style="background: #cef2e0;" | ID
! style="background: #cef2e0;" | Type
! style="background: #cef2e0;" | Title
! style="background: #cef2e0;" | Customer
! style="background: #cef2e0;" | Status
! style="background: #cef2e0;" | Comments
! style="background: #cef2e0;" | Priority
! style="background: #cef2e0;" | Worker Name
';
	my $tasks = getTasks_inSP($id);
	foreach my $sc (keys %$tasks) {
	    WikiCommons::set_real_path((fileparse(abs_path($0), qr/\.[^.]*/))[1]."");
	    my $cust = WikiCommons::get_correct_customer($tasks->{$sc}->{'CUSTOMER'});
	    if (defined $cust && $cust !~ m/^\s*$/) {
		$cust = "[[:Category:$cust|$cust]]";
	    } else {
		$cust = $tasks->{$sc}->{'CUSTOMER'} ;
	    }
	    $sp_txt .= "|-
| [[SC:$sc|$sc]] || ".$tasks->{$sc}->{'ChangeType'}." || ".$tasks->{$sc}->{'TITLE'}." || $cust || ".$tasks->{$sc}->{'STATUS'}." || ".$tasks->{$sc}->{'COMMENTS'}." || ".$tasks->{$sc}->{'PRIORITY'}." || ".$tasks->{$sc}->{'WorkerName'}."\n";
# print Dumper($tasks);exit 1;
	    $full_deployment->{$sc} = getClones($sc);
	    $sp_deployment->{$sc} = getClones($sc);
	}
	$sp_txt .= "|}\n\n";
	$our_wiki->wiki_edit_page($sp_bugs->{'page'}, "$sp_txt");
	makeDeploymentPage($sp_deployment);
    }
    $txt .= "$end\n\n";
    makeDeploymentPage($full_deployment);
# print Dumper("$deployment_ns:$sp", "$txt");
    $our_wiki->wiki_edit_page("$deployment_ns:$sp", "$txt");
#     $our_wiki->wiki_delete_page("$deployment_ns:$sp");
#     print Dumper("$deployment_ns:$sp", "$txt");
}
$dbh->disconnect if defined($dbh);
