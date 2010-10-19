#!/usr/bin/perl
#LD_LIBRARY_PATH=./instantclient_11_2/ perl ./oracle.pl
use warnings;
use strict;

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
use File::Find::Rule;
use Mind_work::WikiCommons;
use XML::Simple;
use Encode;

die "We need the destination path.\n" if ( $#ARGV != 0 );
our $to_path = shift;
WikiCommons::makedir ("$to_path");
$to_path = abs_path("$to_path");

my $update_all = "yes";
my $ftp_addr = 'http://62.219.96.62/SupportFTP/';
my $dbh;
my $event_codes = {};
my $attributes = {};
my $attributes_options = {};
my $staff = {};
my $priorities = {};
my $problem_categories = {};
my $problem_types = {};
my $servicestatus = {};

sub print_coco {
    my $nr = shift;
    my @array = qw( \ | / - );
    my $padded = sprintf("%05d", $nr);
    print "running $padded ".$array[$nr%@array]."\r";
}

sub write_file {
    my ($path,$text) = @_;
    open (FILE, ">$path") or die "can't open file $path for writing: $!\n";
    print FILE Encode::encode('utf8', "$text");
    close (FILE);
}

sub get_servicestatus {
    my $SEL_INFO = '
select t.rscservicestatuscode, t.rscservicestatusdesc
  from tblscservicestatus t';
    my $sth = $dbh->prepare($SEL_INFO);
    $sth->execute();
    while ( my @row=$sth->fetchrow_array() ) {
	$servicestatus->{$row[0]} = $row[1];
    }
}

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
	$staff->{$row[0]}->{'last_name'} = $row[1];
	$staff->{$row[0]}->{'first_name'} = $row[2];
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
    return $info;
}

sub get_allsrs {
    my $cust = shift;
    my $SEL_INFO = '
select t1.rsceventsscno, count(t1.rsceventssrno)
  from tblscevents t1
 where t1.rsceventscompanycode = :CUST_CODE
   and t1.rsceventsscno in
       (select t.rscmainrecscno
          from tblscmainrecord t
         where t.rscmainreccustcode = :CUST_CODE
           and t.rscmainreclasteventdate >= \'20070101\')
 group by t1.rsceventsscno';
    my $sth = $dbh->prepare($SEL_INFO);
    $sth->bind_param( ":CUST_CODE", $cust );
    $sth->execute();
    my $info = {};
    while ( my @row=$sth->fetchrow_array() ) {
	$info->{$row[0]} = $row[1];
    }
    return $info;
}

sub get_sr {
    my ($cust, $sc_no) = @_;
    my $SEL_INFO = '
select t.rsceventssrno,
       t.rsceventscode,
       t.rsceventsdate,
       t.rsceventstime,
       t.rsceventscreator,
       t.rsceventsshortdesc,
       t.rsceventsservicestatus,
       t.rsceventsshowcustomer,
       t.rsceventscustcontact
  from tblscevents t
 where t.rsceventscompanycode = :CUST_CODE
   and t.rsceventsscno = :SR_NR
 order by 1';
    my $sth = $dbh->prepare($SEL_INFO);
    $sth->bind_param( ":CUST_CODE", $cust );
    $sth->bind_param( ":SR_NR", $sc_no );
    $sth->execute();
    my $info = {};
    while ( my @row=$sth->fetchrow_array() ) {
	$info->{$row[0]}->{'event'}->{$_} = $event_codes->{$row[1]}->{$_} foreach (keys %{$event_codes->{$row[1]}});
	$info->{$row[0]}->{'date'}->{'date'} = $row[2];
	$info->{$row[0]}->{'date'}->{'time'} = $row[3];
	$info->{$row[0]}->{'person'} = {};
	$info->{$row[0]}->{'person'}->{$_} = $staff->{$row[4]}->{$_} foreach (keys %{$staff->{$row[4]}});
	$info->{$row[0]}->{'short_description'} = $row[5];
	my $desc = get_event_desc($sc_no, $row[0], $cust);
	$info->{$row[0]}->{'description'} = $desc;
	$desc = get_event_reference($sc_no, $row[0], $cust);
	$info->{$row[0]}->{'reference'} = $desc;
	$info->{$row[0]}->{'status'}->{'code'} = $row[6];
	$info->{$row[0]}->{'status'}->{'value'} = $servicestatus->{$row[6]};
	$info->{$row[0]}->{'show_to_customer'} = $row[7];
	$info->{$row[0]}->{'customer_contact'} = get_customer_desc($cust, $row[8]);
    }
    return $info;
}

sub get_sr_desc {
    my ($customer, $srscno) = @_;
    my $info = {};
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
   and t.rscmainrecscno = :SRSCNO';

    my $sth = $dbh->prepare($SEL_INFO);
    $sth->bind_param( ":CUSTOMER", $customer );
    $sth->bind_param( ":SRSCNO", $srscno );
    $sth->execute();
    while ( my @row=$sth->fetchrow_array() ) {
	$info->{'description'} = $row[0];
	$info->{'priority'}->{$_} = $priorities->{$row[1]}->{$_} foreach (keys %{$priorities->{$row[1]}});
	$info->{'incharge'}->{$_} = $staff->{$row[2]}->{$_} foreach (keys %{$staff->{$row[2]}});
	$info->{'date'}->{'time'} = $row[4];
	$info->{'date'}->{'date'} = $row[3];
	$info->{'cust_category'} = $problem_categories->{$row[5]} || $row[5];
	$info->{'type'} = $problem_types->{$row[6]};
	$info->{'solution'} = substr $row[7], 2;
	$info->{'subject'} = $row[8];
	$info->{'mind_category'} = $problem_categories->{$row[9]};
    }
    return $info;
}

sub get_customer_desc {
    my ($cust, $code) = @_;
    my $info = {};

    my $SEL_INFO = '
select t.rcustcontlastname,
       t.rcustcontfirstname,
       t.rcustcontemail,
       t.rcustcontcustdept,
       t.rcustcontposition
  from tblcustomercontacts t
 where t.rcustcontcompanycode = :CUSTOMER
   and t.rcustcontactcode = :CODE';

    my $sth = $dbh->prepare($SEL_INFO);
    $sth->bind_param( ":CUSTOMER", $cust );
    $sth->bind_param( ":CODE", $code );
    $sth->execute();
    while ( my @row=$sth->fetchrow_array() ) {
	$info->{'last_name'} = $row[0];
	$info->{'first_name'} = $row[1];
	$info->{'email'} = $row[2];
	$info->{'department'} = $row[3];
	$info->{'position'} = $row[4];
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
	my $data = substr $row[2], 2;
	$data = $ftp_addr.$data if $row[0] eq 'B';
	$info->{$row[0].$row[1]} = $data;
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

sub write_customer {
    my ($cust, $hash) = @_;
    print "\t-Get customer info.\t". (WikiCommons::get_time_diff) ."\n";
    $hash->{'names'} = $cust;
    my $xs = new XML::Simple;
    my $xml = $xs->XMLout($hash,
                      NoAttr => 1,
                      RootName=>$cust->{'name'},
                     );
    my $dir = "$to_path/".$cust->{'displayname'};
    WikiCommons::makedir ("$dir");
    write_file( "$dir/attributes.xml", $xml);
    print "\t+Get customer info.\t". (WikiCommons::get_time_diff) ."\n";
    return $dir;
}

sub write_sr {
    my ($info, $name) = @_;
    my @keys = keys %$info;
    die "pai da de ce?\n".Dumper($info) if scalar keys %{$info->{$keys[0]}} < 2 ;
    my $xs = new XML::Simple;
    my $xml = $xs->XMLout($info,
                      NoAttr => 1,
                      RootName=>"info",
                     );
    write_file( "$name", $xml);
    foreach my $key (keys %$info){
	my $hash = $info->{$key};
	if ($key == 0){
	    print "$hash->{'solution'}\n\n\n";
	    print "\n";
	    print "\n";
	    print "\n";
	    print "\n";
	    print "\n";
	    print "\n";
	    print "\n";
	    print "\n";
	    print "\n";
	} else {
	}
    }
}

sub get_previous {
    my $dir = shift;
    my $info = {};
    opendir(DIR, "$dir") || die "Cannot open directory $dir: $!.\n";
    my @files = grep { (!/^\.\.?$/) && -f "$dir/$_" && "$_" ne "attributes.xml"} readdir(DIR);
    closedir(DIR);
    foreach my $file (@files){
	my $str = $file;
	$str =~ s/\.xml$//;
	$str =~ s/^0*//;
	my @tmp = split '_', $str;
	$info->{$tmp[0]."_".$tmp[1]} = $file;
    }
    return $info;
}

$ENV{NLS_LANG} = 'AMERICAN_AMERICA.AL32UTF8';
sql_connect('10.0.0.232', 'BILL1022', 'service25', 'service25');
WikiCommons::reset_time();
local $| = 1;
print "-Get common info.\t". (WikiCommons::get_time_diff) ."\n";
get_eventscode();
my $customers = get_customers();
get_attributes();
get_attributes_options();
get_staff();
get_priorities();
get_problem_categories();
get_problem_types();
get_servicestatus();
print "+Get common info.\t". (WikiCommons::get_time_diff) ."\n";
# get_sr_desc(100,1);
# print Dumper($problem_types);
# exit 1;
foreach my $cust (sort keys %$customers){
    print "\tStart for customer $customers->{$cust}->{'displayname'}/$customers->{$cust}->{'name'}:$cust.\t". (WikiCommons::get_time_diff) ."\n";
next if $customers->{$cust}->{'displayname'} ne "Kocnet";
    my $dir = write_customer ($customers->{$cust}, get_customer_attributes($cust));
    my $crt_srs = get_allsrs($cust);
    my $prev_srs = get_previous("$to_path/".$customers->{$cust}->{'displayname'});
    foreach my $key (keys %$crt_srs) {
	last if $update_all eq "yes";
	my $str = $key."_".$crt_srs->{$key};
	if (exists $prev_srs->{$str}) {
	    delete $prev_srs->{$str} ;
	    delete $crt_srs->{$key} ;
	}
    }

    print "\tremove ".(scalar keys %$prev_srs)." old files.\n";
    foreach my $key (keys %$prev_srs) {
	unlink("$dir/$prev_srs->{$key}") or die "Could not delete the file $dir/$prev_srs->{$key}: ".$!."\n";
    }
    print "\tadd ".(scalar keys %$crt_srs)." new files.\n";
    my $nr = 0;
    foreach my $sr (keys %$crt_srs) {
	my $info = {};
	$info = get_sr($cust, $sr);
	my $name = "$dir/".sprintf("%07d", $sr)."_".(scalar keys %$info).".xml";
	my $desc = get_sr_desc($cust, $sr);
	$info->{'0'} = $desc;
	write_sr($info, $name);
	print_coco(++$nr);
    }
}
### links url encoded
$dbh->disconnect if defined($dbh);
# http://62.219.96.62/eServiceReq/mgrqispi93.dll?APPNAME=Service&PRGNAME=SecondFrame&ARGUMENTS=-A001_0000434033E,-N0000$SR,-N001,-N000$CUST
# http://62.219.96.62/eServiceReq/mgrqispi93.dll?APPNAME=Service&PRGNAME=SecondFrame&ARGUMENTS=-A001_0000434033E,-N0000456,-N001,-N000221
#sr 1586, customer 221
# http://62.219.96.62/eServiceReq/mgrqispi93.dll?APPNAME=Service&PRGNAME=SecondFrame&ARGUMENTS=-A001_0000434033E,-N00001586,-N001,-N000221,-N010,-A001_0000434033E,-N000221,-N1,-N00000000,-N000,-N000,-N0000000000,-AFalse,-AFalse,-AFalse,-AFalse,-AFalse,-AALL,-A000000,-A000000,-A000000,-A000000,-N000005,-AFalse,-N000000,-AA,-A,-N000,-N000,-N000,-A,-A,-LFalse,-A,-A000000,-A000000,-A,-LFalse,-N00,-LF,-Akocnet,-A,-AA

#sr 761, customer 328
# http://62.219.96.62/eServiceReq/mgrqispi93.dll?APPNAME=Service&PRGNAME=SecondFrame&ARGUMENTS=-A001_0000434033E,-N00000761,-N001,-N000328,-N011,-A001_0000434033E,-N000328,-N1,-N00000000,-N000,-N000,-N0000000000,-AFalse,-AFalse,-AFalse,-AFalse,-AFalse,-AALL,-A000000,-A000000,-A000000,-A000000,-N000005,-AFalse,-N000000,-AA,-A,-N000,-N000,-N000,-A,-A,-LFalse,-A,-A000000,-A000000,-A,-LFalse,-N00,-LF,-ASRG,-A,-AA
