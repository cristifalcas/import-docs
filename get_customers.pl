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

my $attributes_options = {};
my $dbh;
my $ftp_addr = 'http://62.219.96.62/SupportFTP/';
my $attributes = {};
my $customers = {};

sub write_customer {
    my ($hash) = @_;
    print "\t-Get customer info.\t". (WikiCommons::get_time_diff) ."\n";
    my $dir = "./".$hash->{'names'}->{'displayname'};
    WikiCommons::makedir ("$dir");
#     write_xml($hash, "$dir/attributes");
print Dumper($hash);
    print "\t+Get customer info.\t". (WikiCommons::get_time_diff) ."\n";
    return $dir;
}

sub get_attributes {
    my $SEL_INFO = 'select t.attribisn, t.attribname from tblattributes t';
    my $sth = $dbh->prepare($SEL_INFO);
    $sth->execute();
    while ( my @row=$sth->fetchrow_array() ) {
	$attributes->{$row[0]} = $row[1];
    }
}

sub get_attributes_options {
    my $SEL_INFO = 'select t.attrib_isn, t.option_line, t.option_text from tblattriboptions t';
    my $sth = $dbh->prepare($SEL_INFO);
    $sth->execute();
    while ( my @row=$sth->fetchrow_array() ) {
	$attributes_options->{$row[0]}->{$row[1]} = $row[2];
    }
}

sub get_customer_attributes {
    my $code = shift;
    my $info = {};
    my $SEL_INFO = '
select t.attrib_isn, t.value_text
  from tblattrib_values t
 where attrib_object_code1 = :CUST_CODE';
    my $sth = $dbh->prepare($SEL_INFO);
    $sth->bind_param( ":CUST_CODE", $code );
    $sth->execute();
    my $nr=0;
    while ( my @row=$sth->fetchrow_array() ) {
	my $data = "";
	if (defined $attributes_options->{$row[0]}->{$row[1]}) {
	     $data = $attributes_options->{$row[0]}->{$row[1]};
	} else {
	    $data = $row[1];
	}
	$data =~ s/(^\s*)|(\s*$)//;
	next if $data eq '';
	if ( $row[0] == 23 || $row[0] == 9  || $row[0] == 6 ) {
	    $data = $ftp_addr."/Attrib/".$data;
	}
	$info->{$attributes->{$row[0]}} = $data;
    }
    $info->{'customer_id'} = $code;
    $info->{'names'} = $customers->{$code};
    return $info;
}

$ENV{NLS_LANG} = 'AMERICAN_AMERICA.AL32UTF8';

$dbh=DBI->connect("dbi:Oracle:host=10.0.0.232;sid=BILL1022", "service25", "service25")|| die( $DBI::errstr . "\n" );
$dbh->{AutoCommit}    = 0;
$dbh->{RaiseError}    = 1;
$dbh->{ora_check_sql} = 1;
$dbh->{RowCacheSize}  = 0;
#     $dbh->{LongReadLen}   = 52428800;
$dbh->{LongReadLen} = 1024 * 1024;
$dbh->{LongTruncOk}   = 0;

    my $SEL_INFO = '
select t.rcustcompanycode, t.rcustcompanyname, t.rcustiddisplay
  from tblcustomers t';
#     where t.rcuststatus = \'A\'
my $sth = $dbh->prepare($SEL_INFO);
$sth->execute();

get_attributes_options();
get_attributes();

while ( my @row=$sth->fetchrow_array() ) {
    die "Already have this id for cust.\n" if exists $customers->{$row[0]};
    $customers->{$row[0]}->{'name'} = $row[1];
    $customers->{$row[0]}->{'displayname'} = $row[2];

    my $cust_info = get_customer_attributes($row[0]);
    next if (! defined $cust_info->{'Latest Version'} || $cust_info->{'Latest Version'} lt "5.00")
	    && $customers->{$row[0]}->{'displayname'} ne "Billing";

    my $dir = write_customer ($cust_info);
}

$dbh->disconnect if defined($dbh);

WikiCommons::hash_to_xmlfile($customers, "./customers.xml", "customers");
# $customers = WikiCommons::xmlfile_to_hash ("./customers.xml");
# print Dumper($customers);
