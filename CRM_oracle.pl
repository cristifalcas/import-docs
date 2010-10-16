#!/usr/bin/perl
#LD_LIBRARY_PATH=./instantclient_11_2/ perl ./oracle.pl
use warnings;
use strict;

# select t.rcustcompanycode, t.rcustcompanyname, t.rcustiddisplay, t.*
#   from tblcustomers t where t.rcuststatus == 'A';
# select t.rsceventsscno, t.rsceventssrno, t.rsceventscode, t.rsceventsdate,t.rsceventstime,
#        t.rsceventscreator, t.rsceventsshortdesc, t.rsceventsservicestatus,t.*
#   from tblscevents t where t.rsceventscompanycode = '485' order by 1,2;-- rcustcompanycode
# select t.rscmainproblemdescription,t.rscmainreccustomerpriority,t.rscmainrecenggincharge,
#        t.rscmainreclasteventdate,t.rscmainreclasteventtime,t.rscmainrecprobcatg,t.rscmainrecsctype,t.rscmainrecsolution,
#        t.rscmainrecsubject,t.rscmainrectsinternalpriority,t.*
#   from tblscmainrecord t where t.rscmainreccustcode='485' and t.rscmainrecscno='2';
# select t.rsceventsrno,t.rsceventdocno,t.rsceventdocscno,t.rsceventdoctype,t.rsceventdoctype,t.*
#   from tblsceventdoc t where t.rsceventdoccompanycode='485' and t.rsceventdocscno='1';
# select t.attrib_object_code1,t.*
#   from tblattrib_values t where attrib_object_code1='485';
# select *
#   from tblattributes;
# select t.rsuppeventscode,t.*
#   from tblsuppevents t;
# select *
#   from tblacttreeitems t;
# select *
#   from tblattriboptions t; --??
# select t.rscrefeventsrno,t.rscrefscno,t.*
#   from tblscrefnum t where t.rscrefcust='485' and (trim(' ' from NVL(t.rscrefnum1,'')) is not null
#             or trim(' ' from NVL(t.rscrefnum2,'')) is not null);

use lib "./our_perl_lib/lib";
use DBI;
use Net::FTP;
use LWP::UserAgent;
use File::Path qw(make_path remove_tree);
use Data::Dumper;
$Data::Dumper::Sortkeys = 1;
use File::Basename;
use File::Listing qw(parse_dir);
use File::Find;
use File::Copy;
use Cwd 'abs_path','chdir';
use XML::Simple;
use File::Find::Rule;
use Data::Compare;
use Mind_work::WikiCommons;

my $dbh;
my $event_codes = {};
my $attributes = {};
my $attributes_options = {};
my $staff = {};
my $priorities = {};
my $problem_categories = {};
my $problem_types = {};

sub get_eventscode {
    my $SEL_INFO = '
select t.rsuppeventscode, t.rsuppeventsdesc, t.rsuppeventsdefsupstatus
  from tblsuppevents t';
    my $sth = $dbh->prepare($SEL_INFO);
    $sth->execute();
    while ( my @row=$sth->fetchrow_array() ) {
	$event_codes->{$row[0]}->{'desc'} = $row[1];
	$event_codes->{$row[0]}->{'status'} = $row[2];
    }
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

sub get_staff {
    my $SEL_INFO = '
select t.rsuppstaffenggcode,
       t.rsuppstafflastname,
       t.rsuppstafffirstname,
       t.rsuppstaffemail
  from tblsupportstaff t';
    my $sth = $dbh->prepare($SEL_INFO);
    $sth->execute();
    while ( my @row=$sth->fetchrow_array() ) {
	$staff->{$row[0]}->{'name'} = $row[2]." ".$row[1];
	$staff->{$row[0]}->{'email'} = $row[3];
    }
}

sub get_priorities {
    my $SEL_INFO = '
select t.rsupppriorities, t.rsuppprioritiesdesc, t.colorforlistofspr
  from tblsupppriorities t';
    my $sth = $dbh->prepare($SEL_INFO);
    $sth->execute();
    while ( my @row=$sth->fetchrow_array() ) {
	$priorities->{$row[0]}->{'description'} = $row[1];
	$priorities->{$row[0]}->{'color'} = $row[2];
    }
}

sub get_problem_categories {
    my $SEL_INFO = 'select t.rprobcatgcode, t.rprobcatgdesc from tblproblemcategories t';
    my $sth = $dbh->prepare($SEL_INFO);
    $sth->execute();
    while ( my @row=$sth->fetchrow_array() ) {
	$problem_categories->{$row[0]} = $row[1];
    }
}

sub get_problem_types {
    my $SEL_INFO = 'select t.rsctypescode, t.rsctypesdesc from tblsctypes t';
    my $sth = $dbh->prepare($SEL_INFO);
    $sth->execute();
    while ( my @row=$sth->fetchrow_array() ) {
	$problem_types->{$row[0]} = $row[1];
    }
}

sub get_customers {
    my $info = {};
    my $SEL_INFO = '
select t.rcustcompanycode, t.rcustcompanyname, t.rcustiddisplay
  from tblcustomers t
 where t.rcuststatus = \'A\'';
    my $sth = $dbh->prepare($SEL_INFO);
    $sth->execute();
    while ( my @row=$sth->fetchrow_array() ) {
	die "Already have this id for cust.\n" if exists $info->{$row[0]};
	$info->{$row[0]}->{'name'} = $row[1];
	$info->{$row[0]}->{'displayname'} = $row[2];
    }
    return $info;
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
	if (defined $attributes_options->{$row[0]}->{$row[1]}) {
	    $info->{$attributes->{$row[0]}} = $attributes_options->{$row[0]}->{$row[1]};
	} else {
	    $info->{$attributes->{$row[0]}} = $row[1];
	}
    }
# 'System Description Document' 'Support Team Manager' 'Project Manager' 'Last Plug Information' 'DBA service' 'Database Type' 'Account Manager'
# remove 'Additional Service  schedule and description'
    return $info;
}

sub get_allsrs {
    my $code = shift;
    my $info = {};
    my $SEL_INFO = '
select t.rsceventsscno,
       t.rsceventssrno,
       t.rsceventscode,
       t.rsceventsdate,
       t.rsceventstime,
       t.rsceventscreator,
       t.rsceventsshortdesc
  from tblscevents t
 where t.rsceventscompanycode = :CUST_CODE';
    my $sth = $dbh->prepare($SEL_INFO);
    $sth->bind_param( ":CUST_CODE", $code );
    $sth->execute();
    my $nr=0;
    while ( my @row=$sth->fetchrow_array() ) {
	my $desc = get_sr_desc($row[0], $code);
	next if ! defined $desc;
	$info->{$row[0]}->{'description'} = $desc if ! exists $info->{$row[0]}->{'description'};
	$info->{$row[0]}->{$row[1]}->{'event'}->{$_} = $event_codes->{$row[2]}->{$_} foreach (keys %{$event_codes->{$row[2]}});
	$info->{$row[0]}->{$row[1]}->{'date'} = $row[3]." ".$row[4];
	$info->{$row[0]}->{$row[1]}->{'person'}->{$_} = $staff->{$row[5]}->{$_} foreach (keys %{$staff->{$row[5]}});
	$info->{$row[0]}->{$row[1]}->{'short_description'} = $row[6];
	$desc = get_event_desc($row[0], $row[1], $code);
	$info->{$row[0]}->{$row[1]}->{'description'} = $desc;
	$desc = get_event_reference($row[0], $row[1], $code);
	$info->{$row[0]}->{$row[1]}->{'reference'} = $desc;
    }
    return $info;
}

sub get_sr_desc {
    my ($srscno, $customer) = @_;
    my $info = {};
# DBI->trace(3);

    my $SEL_INFO = '
select t.rscmainproblemdescription,
       t.rscmainreccustomerpriority,
       t.rscmainrecenggincharge,
       t.rscmainreclasteventdate,
       t.rscmainreclasteventtime,
       t.rscmainrecprobcatg,
       t.rscmainrecsctype,
       t.rscmainrecsolution,
       t.rscmainrecsubject,
       t.rscmainrectsinternalpriority
  from tblscmainrecord t
 where t.rscmainreccustcode = :CUSTOMER
   and t.rscmainrecscno = :SRSCNO
   and t.rscmainreclasteventdate >= \'20100101\'';

    my $sth = $dbh->prepare($SEL_INFO);
    $sth->bind_param( ":CUSTOMER", $customer );
    $sth->bind_param( ":SRSCNO", $srscno );
    $sth->execute();
    while ( my @row=$sth->fetchrow_array() ) {
	$info->{'description'} = $row[0];
	$info->{'priority'}->{$_} = $priorities->{$row[1]}->{$_} foreach (keys %{$priorities->{$row[1]}});
	$info->{'incharge'}->{$_} = $staff->{$row[2]}->{$_} foreach (keys %{$staff->{$row[2]}});
	$info->{'date'} = $row[4]." ".$row[3];
	$info->{'cust_category'} = $problem_categories->{$row[5]} || $row[5];
	$info->{'type'} = $problem_types->{$row[6]};
	$info->{'solution'} = $row[7];
	$info->{'subject'} = $row[8];
	$info->{'mind_category'} = $problem_categories->{$row[9]};
    }
    return $info;
}

sub get_event_desc {
    my ($scno, $srno, $customer) = @_;
    my $info = {};

    my $SEL_INFO = '
select t.rsceventdoctype,
       t.rsceventdocno,
       t.rsceventdocpath
  from tblsceventdoc t
 where t.rsceventdoccompanycode = :CUSTOMER
   and t.rsceventdocscno = :SCNO
   and t.rsceventsrno = :SRNO';

    my $sth = $dbh->prepare($SEL_INFO);
    $sth->bind_param( ":CUSTOMER", $customer );
    $sth->bind_param( ":SCNO", $scno );
    $sth->bind_param( ":SRNO", $srno );
    $sth->execute();
    while ( my @row=$sth->fetchrow_array() ) {
	die "too many rows: $scno, $srno, $customer\n" if exists $info->{$row[0]};
	$info->{$row[0].$row[1]} = $row[2];
    }
    return $info;
}

sub get_event_reference {
    my ($scno, $srno, $customer) = @_;
    my $info = {};

    my $SEL_INFO = '
select t.rscrefnum1, t.rscrefnum2
  from tblscrefnum t
 where (trim(\' \' from NVL(t.rscrefnum1, \'\')) is not null or
       trim(\' \' from NVL(t.rscrefnum2, \'\')) is not null)
   and t.rscrefcust = :CUSTOMER
   and t.rscrefscno = :SCNO
   and t.rscrefeventsrno = :SRNO';

    my $sth = $dbh->prepare($SEL_INFO);
    $sth->bind_param( ":CUSTOMER", $customer );
    $sth->bind_param( ":SCNO", $scno );
    $sth->bind_param( ":SRNO", $srno );
    $sth->execute();
    while ( my @row=$sth->fetchrow_array() ) {
	$info->{'ref1'} = $row[0];
	$info->{'ref2'} = $row[1];
    }
    return $info;
}

sub sql_connect {
    my ($ip, $sid, $user, $pass) = @_;
    $dbh=DBI->connect("dbi:Oracle:host=$ip;sid=$sid", "$user", "$pass")|| die( $DBI::errstr . "\n" );
    $dbh->{AutoCommit}    = 0;
    $dbh->{RaiseError}    = 1;
    $dbh->{ora_check_sql} = 1;
    $dbh->{RowCacheSize}  = 0;
#     $dbh->{LongReadLen}   = 52428800;
    $dbh->{LongReadLen} = 1024 * 1024;
    $dbh->{LongTruncOk}   = 0;
}

$ENV{NLS_LANG} = 'AMERICAN_AMERICA.AL32UTF8';
sql_connect('10.0.0.232', 'BILL1022', 'service25', 'service25');

get_eventscode();
my $customers = get_customers();
get_attributes();
get_attributes_options();
get_staff();
get_priorities();
get_problem_categories();
get_problem_types();
# get_sr_desc(100,1);
# print Dumper($event_codes);
foreach my $cust (sort keys %$customers){
    $customers->{$cust}->{'attributes'} = get_customer_attributes($cust);
    $customers->{$cust}->{'srs'} = get_allsrs($cust);
    print "$cust".Dumper($customers->{$cust});
}
$dbh->disconnect if defined($dbh);
