#!/usr/bin/perl -w
#LD_LIBRARY_PATH=./instantclient_11_2/ perl ./oracle.pl
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

our $dbh;

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
 where actual_build_date > '1jan2010'
   and b.productid = a.product
   and a.projectcode = c.projectcode
 order by projectname, productname, version desc, service_pack desc";
    my $info;
    my $sth = $dbh->prepare($SEL_INFO);

    $sth->execute();
    while ( my @row=$sth->fetchrow_array() ) {
	push @$info, \@row;
    }
    return $info;
}

sub getTasks_inSP {
    my $sp = shift;
    my $SEL_INFO = "
SELECT T1.CHANGEID,
       T1.CUSTOMER,
       T1.PRIORITY,
       T1.ChangeType,
       T1.STATUS,
       T1.TITLE,
       T1.COMMENTS,
       i.WorkerName InitiatorName
  FROM SCChange T1, SC_PLANS p, SC_BUILD_MANAGER b, SCWork i
 WHERE  T1.Product IS NOT NULL
   AND T1.ChangeId = p.CHANGE_ID
   AND b.ID(+) = p.BUILD_ID
   AND to_number(T1.Initiator) = i.ID(+)
   AND p.build_id = :SP_ID
 ORDER BY ChangeId";
    my $info;
    my $sth = $dbh->prepare($SEL_INFO);
    $sth->bind_param( ":SP_ID", $sp );
    $sth->execute();
    while ( my @row=$sth->fetchrow_array() ) {
	push @$info, \@row;
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
	push @$info, $change_id;
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

$ENV{NLS_LANG} = 'AMERICAN_AMERICA.AL32UTF8';
sql_connect('10.0.0.103', 'SCROM', 'scview', 'scview');
my $urlsep = WikiCommons::get_urlsep;
my $projects_title = "Software projects";
# print Dumper(getProjects);exit 1;
foreach (my @row = @{getProjects()}){
print Dumper(@row);
}
exit 1;
my $sps = getSPs;
foreach my $sp_id (@$sps) {
    my ($id,$projectname,$productname,$version,$service_pack,$build_type,$description,$actual_build_date) = @$sp_id;
    my ($big_ver, $main_v, $ver_v, $ver_fixed, $ver_sp, $ver_id) = WikiCommons::check_vers($version, $version);
#     my $prod_page->{'title'} = "$projectname$urlsep$productname";
#     my $prod_page->{'text'} = "[[Category:$projectname]]";
#     my $proj_page->{'title'} = "$projectname$urlsep$productname";
#     my $proj_page->{'text'} = "[[Category:$projectname]]";
# $big_ver -> $main_v -> $ver_fixed
# Category:Projects
# $projectname -> $productname
# $projectname -- $productname -- Service Packs
# $projectname -- $productname -- Service Pack -- $version $service_pack
# $version $service_pack $service_pack $description $actual_build_date
print Dumper($sp_id);
}
# getTasks_inSP('76902');
# getClones('B106037');
$dbh->disconnect if defined($dbh);
