#!/usr/bin/perl

use warnings;
use strict;

$SIG{__WARN__} = sub { die @_ };

BEGIN {
    my $need= "./instantclient_11_2/";
    my $ld= $ENV{LD_LIBRARY_PATH};
    if(  ! $ld  ) {
        $ENV{LD_LIBRARY_PATH}= $need;
    } elsif(  $ld !~ m#(^|:)\Q$need\E(:|$)#  ) {
        $ENV{LD_LIBRARY_PATH} .= ':' . $need;
    } else {
        $need= "";
    }
    if( $need ) {
        exec 'env', $^X, $0, @ARGV;
    }
}

use Cwd 'abs_path','chdir';
use File::Basename;
use lib (fileparse(abs_path($0), qr/\.[^.]*/))[1]."./our_perl_lib/lib";
use DBI;
use Data::Dumper;
$Data::Dumper::Sortkeys = 1;
use XML::Simple;
use Mind_work::WikiCommons;

$ENV{NLS_LANG} = 'AMERICAN_AMERICA.AL32UTF8';
my $dbh;
$dbh=DBI->connect("dbi:Oracle:host=10.0.0.232;sid=BILL1022", "service25", "service25")|| die( $DBI::errstr . "\n" );
$dbh->{AutoCommit}    = 0;
$dbh->{RaiseError}    = 1;
$dbh->{ora_check_sql} = 1;
$dbh->{RowCacheSize}  = 0;
#     $dbh->{LongReadLen}   = 52428800;
$dbh->{LongReadLen} = 1024 * 1024;
$dbh->{LongTruncOk}   = 0;

my $SEL_INFO = 'select t.rcustcompanycode, t.rcustcompanyname, t.rcustiddisplay
    from tblcustomers t
    where t.rcuststatus = \'A\'';
my $sth = $dbh->prepare($SEL_INFO);
$sth->execute();
my $customers = {};
while ( my @row=$sth->fetchrow_array() ) {
    die "Already have this id for cust.\n" if exists $customers->{$row[0]};
    $customers->{"nr".$row[0]}->{'name'} = $row[1];
    $customers->{"nr".$row[0]}->{'displayname'} = $row[2];
}
$dbh->disconnect if defined($dbh);

WikiCommons::hash_to_xmlfile($customers, "./customers.xml", "customers");
# $customers = WikiCommons::xmlfile_to_hash ("./customers.xml");
# print Dumper($customers);
