#!/usr/bin/perl
#LD_LIBRARY_PATH=./instantclient_11_2/ perl ./oracle.pl
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
    if(  $need  ) {
        exec 'env', $^X, $0, @ARGV;
    }
}

#
# hash:
#     event number 0
# 	$info->{'cust_category'}
# 	$info->{'customer'}
# 	$info->{'date'}->{'date'}
# 	$info->{'date'}->{'time'}
# 	$info->{'desc'}
# 	$info->{T,B,.N}
# 	$info->{'incharge'}->{'email'}
# 	$info->{'incharge'}->{'first_name'}
# 	$info->{'incharge'}->{'last_name'}
# 	$info->{'incharge'}->{'job'}	-- not used
# 	$info->{'last_date'}->{'date'}	-- not used
# 	$info->{'last_date'}->{'time'}	-- not used
# 	$info->{'mind_category'}
# 	$info->{'number'}
# 	$info->{'priority'}->{'color'}	-- not used
# 	$info->{'priority'}->{'desc'}	-- not used
# 	$info->{'solution'}
# 	$info->{'subject'}
# 	$info->{'type'}
#
#     event number N
# 	$info->{N}->{'customer_contact'}->{'department'}
# 	$info->{N}->{'customer_contact'}->{'email'}
# 	$info->{N}->{'customer_contact'}->{'first_name'}
# 	$info->{N}->{'customer_contact'}->{'last_name'}
# 	$info->{N}->{'customer_contact'}->{'position'}
# 	$info->{N}->{'date'}->{'date'}
# 	$info->{N}->{'date'}->{'time'}
# 	$info->{N}->{'description'}
# 	$info->{N}->{'event'}->{'code'}
# 	$info->{N}->{'event'}->{'desc'}
# 	$info->{N}->{'person'}->{'email'}
# 	$info->{N}->{'person'}->{'first_name'}
# 	$info->{N}->{'person'}->{'last_name'}
# 	$info->{N}->{'person'}->{'job'}	-- not used
# 	$info->{N}->{'reference'}	-- not used
# 	$info->{N}->{'short_desc'}
# 	$info->{N}->{'show_to_customer'}
# 	$info->{N}->{'status'}->{'code'}
# 	$info->{N}->{'status'}->{'desc'}


use Cwd 'abs_path','chdir';
use File::Basename;
use lib (fileparse(abs_path($0), qr/\.[^.]*/))[1]."./our_perl_lib/lib";
use DBI;
use Net::FTP;
use LWP::UserAgent;
use File::Path qw(make_path remove_tree);
use Data::Dumper;
$Data::Dumper::Sortkeys = 1;
use File::Listing qw(parse_dir);
use File::Find;
use File::Copy;
use File::Find::Rule;
use Mind_work::WikiCommons;
use XML::Simple;
use Encode;
use URI::Escape;
use HTML::TreeBuilder;
use Mind_work::WikiClean;
use Mind_work::WikiWork;

die "We need the destination path.\n" if ( $#ARGV != 0 );
our $to_path = shift;
WikiCommons::makedir ("$to_path");
$to_path = abs_path("$to_path");

my $update_all = "no";
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
my $customers = {};

sub get_encoding {
    my $txt = shift;
#     return $txt if $txt =~ m/\s*/;
#     $txt = 'services key';
# write_file('./1', $txt);die;
    use Encode::Guess;# qw/latin1 utf8  cp1251 iso-8859-1 iso-8859-2/;
#     use Encode::Guess Encode->encodings(":all");
# print Dumper(Encode->encodings(":all"));exit 1;
#     use Encode;
    my $enc = guess_encoding($txt, qw/cp1251 utf8 iso-8859-1/);
    print "Can't guess: $enc.\n", return '' if (!ref($enc));
#     print Dumper($enc->name);
# write_file('./test1',$txt);
# write_file('./test',decode('latin1',$txt));
#     my $utf = $enc->name."\n".$enc->decode($txt);
# print "$utf\n";die;
# decode('utf8',$utf);
#     return $enc->decode($txt);
    return $enc->name;
}

sub print_coco {
    my ($nr, $total) = @_;
    my @array = qw( \ | / - );
    my $padded = sprintf("%05d", $nr);
    print "\t\t\t\trunning $padded out of $total".$array[$nr%@array]." \r";
}

sub write_xml {
    my ($info, $name) = @_;
    my $xs = new XML::Simple;
    my $xml = $xs->XMLout($info,
                      NoAttr => 1,
                      RootName=>"info",
                     );
    write_file( "$name.xml", $xml);
}

sub write_file {
    my ($path, $text) = @_;
    open (FILE, ">$path") or die "can't open file $path for writing: $!\n";
    $text = encode("utf8", $text);
    print FILE "$text";
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
	$event_codes->{$row[0]}->{'code'} = $row[2];
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
       t.rsuppstaffemail,
       p.rtechservjobsname
  from tblsupportstaff t, tbltechservjobs p
 where t.rsuppstaffjob = p.rtechservjobscode';
    my $sth = $dbh->prepare($SEL_INFO);
    $sth->execute();
    while ( my @row=$sth->fetchrow_array() ) {
	$staff->{$row[0]}->{'last_name'} = $row[1];
	$staff->{$row[0]}->{'first_name'} = $row[2];
	$staff->{$row[0]}->{'email'} = $row[3];
	$staff->{$row[0]}->{'job'} = $row[4];
    }
}

sub get_priorities {
    my $SEL_INFO = '
select t.rsupppriorities, t.rsuppprioritiesdesc, t.colorforlistofspr
  from tblsupppriorities t';
    my $sth = $dbh->prepare($SEL_INFO);
    $sth->execute();
    while ( my @row=$sth->fetchrow_array() ) {
	$priorities->{$row[0]}->{'desc'} = $row[1];
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
    my $SEL_INFO = '
select t.rcustcompanycode, t.rcustcompanyname, t.rcustiddisplay
  from tblcustomers t
 where t.rcuststatus = \'A\'';
    my $sth = $dbh->prepare($SEL_INFO);
    $sth->execute();
    while ( my @row=$sth->fetchrow_array() ) {
	die "Already have this id for cust.\n" if exists $customers->{$row[0]};
	$customers->{$row[0]}->{'name'} = $row[1];
	$customers->{$row[0]}->{'displayname'} = $row[2];
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
	   and t.rscmainrecdeptcode = 1
           and t.rscmainreclasteventdate >= \'20000101\')
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
	$info->{$row[0]}->{'customer_contact'} = get_customer_desc($cust, $row[8]);
	$info->{$row[0]}->{'person'}->{$_} = $staff->{$row[4]}->{$_} foreach (keys %{$staff->{$row[4]}});
# print Dumper($info->{$row[0]}->{'person'});
	$info->{$row[0]}->{'short_desc'} = $row[5];
	my $desc = get_event_desc($sc_no, $row[0], $cust);
	$info->{$row[0]}->{'description'} = $desc;
	$desc = get_event_reference($sc_no, $row[0], $cust);
	$info->{$row[0]}->{'reference'} = $desc;
	$info->{$row[0]}->{'status'}->{'code'} = $row[6];
	$info->{$row[0]}->{'status'}->{'desc'} = $servicestatus->{$row[6]} || '';
	$info->{$row[0]}->{'show_to_customer'} = $row[7];
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
       t.rscmainrecopendate,
       t.rscmainrecopentime,
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
	$info->{'desc'} = $row[0];
	$info->{'priority'}->{$_} = $priorities->{$row[1]}->{$_} foreach (keys %{$priorities->{$row[1]}});
	$info->{'incharge'}->{$_} = $staff->{$row[2]}->{$_} foreach (keys %{$staff->{$row[2]}});
	$info->{'date'}->{'time'} = $row[4];
	$info->{'date'}->{'date'} = $row[3];
	$info->{'last_date'}->{'time'} = $row[4];
	$info->{'last_date'}->{'date'} = $row[3];
	$info->{'cust_category'} = $problem_categories->{$row[7]} || $row[7];
	$info->{'type'} = $problem_types->{$row[8]};
# 	$info->{'solution'} = get_encoding(substr $row[9], 2);
	$info->{'solution'} = substr $row[9], 2;
	$info->{'subject'} = $row[10];
	$info->{'mind_category'} = $problem_categories->{$row[11]};
    }
    $info->{'number'} = $srscno;
    $info->{'customer'} = $customers->{$customer}->{'displayname'};
    return $info;
}

sub get_customer_desc {
    my ($cust, $code) = @_;
    my $info = {};
    return $info if $code == 0;

    my $SEL_INFO = '
select t.rcustcontlastname,
       t.rcustcontfirstname,
       t.rcustcontemail,
       t.rcustcontcustdept,
       t.rcustcontposition,
       t.rcustcontdirectphone,
       t.rcustcontmobilephno
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
	$info->{'phone'} = $row[5];
	$info->{'phone_mobile'} = $row[6];
    }
    print "Customer code $code does not exists anymore.\n" if ! keys %$info;
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
# 	my $data = get_encoding(substr $row[2], 2);
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
    $dbh->{LongReadLen} = 1024 * 1024;
    $dbh->{LongTruncOk}   = 0;
}

sub write_customer {
    my ($hash) = @_;
    print "\t-Get customer info.\t". (WikiCommons::get_time_diff) ."\n";
    my $dir = "$to_path/".$hash->{'names'}->{'displayname'};
    WikiCommons::makedir ("$dir");
    write_xml($hash, "$dir/attributes");
    print "\t+Get customer info.\t". (WikiCommons::get_time_diff) ."\n";
    return $dir;
}

sub parse_text {
    my ($text, $extra_info) = @_;
    return $text if $text =~ m/^\s*$/;

    my $init_text = $text;
    $text =~ s/\r?\n/\n/g;
    if (defined $extra_info) {
	my $tmp = quotemeta $extra_info->{'subject'};
	$text =~ s/Subject:[ ]+$tmp\nDate:[ ]+$extra_info->{event_date}\n+//;
	$tmp = quotemeta("*************************************************");
	my $reg_exp = "MIND CTI Support Center\n+[a-zA-Z0-9 ]{0,}\n+$tmp\n+Service Call Data:\n+Number:[ ]+$extra_info->{'customer'} \/ $extra_info->{'sr_no'}\n+Received:[ ]+$extra_info->{sr_date}\n+Current Status:[ ]+[a-zA-Z0-9 ]{1,}\n+$tmp\n+PLEASE DO NOT REPLY TO THIS EMAIL - Use the CRM\n*";

	$text =~ s/$reg_exp//gs;
    }

    my $enc = get_encoding($text);
    if ($enc eq "utf8"){
	$text = encode ("utf8", $text);
	$text = WikiClean::fix_wiki_chars( $text );
    }



    $text = WikiClean::fix_wiki_link_to_sc( $text );
    $text = WikiClean::fix_small_issues( $text );
    $text =~ s/([^\n])\n([^\n])/$1\n\n$2/gm;
    $text =~ s/^=/<br\/>=/gm;
    $text =~ s/^\*/<br\/>*/gm;
    $text =~ s/^#/<br\/>#/gm;
    $text =~ s/^(~+)([^~])/<nowiki>$1<\/nowiki>$2/gm;
    return $text;
}

sub write_intro {
    my ($hash, $date, $time) = @_;
    my $wiki =  "<center>\'\'\'$hash->{'subject'}\'\'\'</center>\n";
    $wiki .=  "<p align=\"right\">$time $date</p>\n\n";
    $wiki .=  "\'\'\'Incharge\'\'\': $hash->{'incharge'}->{'first_name'} $hash->{'incharge'}->{'last_name'} ([mailto:$hash->{'incharge'}->{'email'} $hash->{'incharge'}->{'email'}])\n" if (keys %{$hash->{'incharge'}});
    my $type = $hash->{'type'} || '';
    $wiki .="
{| {{prettytable}}
| \'\'\'Type\'\'\'
| \'\'\'Category\'\'\'
| \'\'\'Customer category\'\'\'
|-
| $type
| $hash->{'mind_category'}
| $hash->{'cust_category'}
|}\n\n";
    my $text = parse_text($hash->{'solution'}, undef);
    my $tmp = parse_text($hash->{'desc'}, undef);
    $wiki .=  "\'\'\'Description\'\'\': $tmp\n\n";
    $wiki .=  "\'\'\'Solution\'\'\':\n\n$text\n----\n";
    return $wiki;
}

sub get_time_date {
    my $hash = shift;
    my $time = (substr $hash->{'time'}, 0 , 2).":".(substr $hash->{'time'}, 2 , 2).":".(substr $hash->{'time'}, 4);
    my $date = (substr $hash->{'date'}, 6)."/".(substr $hash->{'date'}, 4 , 2)."/".(substr $hash->{'date'}, 0 , 4);
    return ($date, $time);
}

sub write_header {
    my ($hash, $name, $date, $time, $key) = @_;
#     $wiki .= "<font color=\"#888888\">\n";
    my $wiki .= "<div style=\"background-color:#FDE4AD;\">\n<p>";
    $wiki .= "\n----\n";
    my $tmp = $hash->{'short_desc'};
    $tmp = parse_text($tmp, undef);

    $wiki .= "\'\'\'Description\'\'\': $tmp ";
    $wiki .= "<div style=\"float: right;\">$time $date</div>\n\n";
    $wiki .= "\'\'\'From\'\'\': $name\n\n";
    $wiki .= "\'\'\'Event $key\'\'\': $hash->{event}->{desc} ($hash->{event}->{code}) \'\'\'Status\'\'\': $hash->{status}->{desc} ($hash->{status}->{code}) <div style=\"float: right;\">\'\'\'Customer visible\'\'\': $hash->{show_to_customer}</div>\n\n";
#     $wiki .= "</font>\n\n";
    $wiki .= "----\n";
    $wiki .= "</p>\n</div>\n\n";
    return $wiki;
}

sub get_color {
    my ($hash, $extra_info, $date, $time) = @_;
    my $event_from_mind = 0;
    my $name = "";
    my $color = "";

    $extra_info->{'event_date'} = "$date";
    if ($hash->{'show_to_customer'} ne '1') {
	### this is a mind message
# 	$color = "<font color=\"#2B1B17\">\n";
	$color = "<font color=\"grey\">\n";
	if (scalar keys %{$hash->{'person'}}) {
	    $name = "$hash->{'person'}->{'first_name'} $hash->{'person'}->{'last_name'} ([mailto:$hash->{'person'}->{'email'} $hash->{'person'}->{'email'}])";
	}
	$event_from_mind = 1;
    } elsif (keys %{$hash->{'person'}}) {
	### this is a mind message
	$color = "<font >\n";
	$name = "$hash->{'person'}->{'first_name'} $hash->{'person'}->{'last_name'} ([mailto:$hash->{'person'}->{'email'} $hash->{'person'}->{'email'}])";
	$event_from_mind = 1;
    } elsif (keys %{$hash->{'customer_contact'}}) {
	### this is a customer message
	$color = "<font color=\"blue\">\n";
	my $dept = "";
	my $pos = "";
	$dept = "department = $hash->{customer_contact}->{department}" if $hash->{'customer_contact'}->{'department'} ne ' ';
	$pos = "position = $hash->{customer_contact}->{position}" if $hash->{'customer_contact'}->{'position'} ne ' ';
	$name = "$hash->{'customer_contact'}->{'first_name'} $hash->{'customer_contact'}->{'last_name'} ([mailto:$hash->{'customer_contact'}->{'email'} $hash->{'customer_contact'}->{'email'}]);\nPhone = $hash->{'customer_contact'}->{'phone'}; Mobile phone = $hash->{'customer_contact'}->{'phone_mobile'}\n$dept; $pos";
    } else {
	$color = "<font color=\"#0000FF\">\n";
	print "\tNo customer and no mind engineer. Maybe a customer message.\n";
    }
    $name = parse_text($name, undef);
    return ($name, $color, $event_from_mind);
}

sub write_sr {
    my $info = shift;
    my @keys = keys %$info;
    die "pai da de ce?\n".Dumper($info) if scalar keys %{$info->{$keys[0]}} < 2 ;
    my $extra_info = {};
    my $wiki = "";
    foreach my $key (sort {$a<=>$b} keys %$info){
	my $hash = $info->{$key};
	my ($date, $time) = get_time_date($hash->{'date'});
	if ($key == 0){
	    $wiki = write_intro($hash, $date, $time);
	    $extra_info->{'sr_date'} = "$date";
	    $extra_info->{'customer'} = "$hash->{'customer'}";
	    $extra_info->{'sr_no'} = "$hash->{'number'}";
	    $extra_info->{'subject'} = "$hash->{'subject'}";
	} else {
	    my ($name, $color, $event_from_mind) = get_color($hash, $extra_info, $date, $time);
	    ### Header
	    if ( ! defined $hash->{'event'} ){
		print "No event code for event $key.\n";
		$hash->{'event'}->{'code'} = '';
		$hash->{'event'}->{'desc'} = '';
	    }
	    $wiki .= write_header($hash, $name, $date, $time, $key);

	    my $attachements = "";
	    my $sr_text = "";
	    foreach my $desc (sort keys %{$hash->{'description'}}){
		if ( $desc =~ m/^T[0-9]{1}$/) {
		    my $text = parse_text($hash->{'description'}->{$desc}, $event_from_mind?$extra_info:undef);
		    $sr_text .= "$text\n\n";
		} elsif ( $desc =~ m/^B[0-9]{1,2}$/) {
		    my $text = $hash->{'description'}->{$desc};
		    $text =~ s/&amp;/&/g;
		    my @arr = split '/', $text;
		    $text =~ s/ /%20/g;
		    my $see = $arr[-1];
		    $see =~ s/^[0-9]{1,}-//;
		    $attachements .= "[$text $see]\n\n";
		} elsif ( $desc =~ m/^U2$/) {
		    $attachements .= "$hash->{'description'}->{$desc}\n\n";
		} elsif ( $desc =~ m/^ [1-9]{1}$/) {
		    my $text = parse_text($hash->{'description'}->{$desc}, $event_from_mind?$extra_info:undef);
		    $sr_text .= "$text\n\n";
		} else {
		    die "Unknown event: $desc.$info->{0}->{'number'}\n";
		}
	    }
# 	    $wiki .= "$color\n$sr_text\n$attachements\n</div>\n" if ($sr_text ne '' || $attachements ne '');
	    $wiki .= "$color\n$sr_text\n$attachements\n</font>\n" if ($sr_text ne '' || $attachements ne '');
	    $wiki .= "----\n";
	}
    }
    $wiki .= "\n\n[[Category:CRM]]\n[[Category:$info->{0}->{'customer'} -- CRM]]\n\n";
    return $wiki;
}

sub get_previous {
    my $dir = shift;
    my $info = {};
    opendir(DIR, "$dir") || die "Cannot open directory $dir: $!.\n";
    my @files = grep { (!/^\.\.?$/) && -f "$dir/$_" && "$_" ne "attributes.xml" && "$_" =~ m/\.wiki$/} readdir(DIR);
    closedir(DIR);
    foreach my $file (@files){
	my $str = $file;
	$str =~ s/\.wiki$//;
	$str =~ s/^0*//;
	my @tmp = split '_', $str;
	$info->{$tmp[0]."_".$tmp[1]} = $file;
    }
    return $info;
}

$ENV{NLS_LANG} = 'AMERICAN_AMERICA.AL32UTF8';
# $ENV{NLS_NCHAR} = 'AMERICAN_AMERICA.UTF8';
sql_connect('10.0.0.232', 'BILL1022', 'service25', 'service25');
WikiCommons::reset_time();
local $| = 1;
print "-Get common info.\t". (WikiCommons::get_time_diff) ."\n";
get_eventscode();
get_customers();
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
    print "\n\tStart for customer $customers->{$cust}->{'displayname'}/$customers->{$cust}->{'name'}:$cust.\t". (WikiCommons::get_time_diff) ."\n";
# next if $customers->{$cust}->{'displayname'} ne "Artelecom";
# next if $cust != 381;
    my $cust_info = get_customer_attributes($cust);
    next if (! defined $cust_info->{'Latest Version'} || $cust_info->{'Latest Version'} lt "5.00")
	    && $customers->{$cust}->{'displayname'} ne "Billing";

    my $dir = write_customer ($cust_info);
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
    my $total = scalar keys %$crt_srs;
    print "\tadd $total new files.\n";
    my $nr = 0;
    foreach my $sr (sort {$a<=>$b} keys %$crt_srs) {
# print "$sr\n";next if $sr <804;
# print "$sr\n";next if $sr < 22;
	my $info = {};
	$info = get_sr($cust, $sr);
	my $name = "$dir/".sprintf("%07d", $sr)."_".(scalar keys %$info);
	$info->{'0'} = get_sr_desc($cust, $sr);
# 	write_xml ($info, $name);
	my $txt = write_sr($info);
	write_file ( "$name.wiki", $txt);
	print_coco(++$nr, $total);
    }
}

# &quot;			"
# &amp;			&
# &lt;			<
# &gt;			>
# &circ;			?
# &tilde;			?
# &ensp;
# &emsp;
# &ndash;			?
# &mdash;			?
# &lsquo;			?
# &rsquo;			?
# &sbquo;			?
# &ldquo;			?
# &rdquo;			?
# &bdquo;			?
# &lsaquo;		?
# &rsaquo;		?
# &euro;			�

# <div style="BACKGROUND-COLOR:silver">
### links url encoded
$dbh->disconnect if defined($dbh);
# http://62.219.96.62/eServiceReq/mgrqispi93.dll?APPNAME=Service&PRGNAME=SecondFrame&ARGUMENTS=-A001_0000434033E,-N0000$SR,-N001,-N000$CUST
# http://62.219.96.62/eServiceReq/mgrqispi93.dll?APPNAME=Service&PRGNAME=SecondFrame&ARGUMENTS=-A001_0000434033E,-N0000456,-N001,-N000221
#sr 1586, customer 221
# http://62.219.96.62/eServiceReq/mgrqispi93.dll?APPNAME=Service&PRGNAME=SecondFrame&ARGUMENTS=-A001_0000434033E,-N00001586,-N001,-N000221,-N010,-A001_0000434033E,-N000221,-N1,-N00000000,-N000,-N000,-N0000000000,-AFalse,-AFalse,-AFalse,-AFalse,-AFalse,-AALL,-A000000,-A000000,-A000000,-A000000,-N000005,-AFalse,-N000000,-AA,-A,-N000,-N000,-N000,-A,-A,-LFalse,-A,-A000000,-A000000,-A,-LFalse,-N00,-LF,-Akocnet,-A,-AA

#sr 761, customer 328
# http://62.219.96.62/eServiceReq/mgrqispi93.dll?APPNAME=Service&PRGNAME=SecondFrame&ARGUMENTS=-A001_0000434033E,-N00000761,-N001,-N000328,-N011,-A001_0000434033E,-N000328,-N1,-N00000000,-N000,-N000,-N0000000000,-AFalse,-AFalse,-AFalse,-AFalse,-AFalse,-AALL,-A000000,-A000000,-A000000,-A000000,-N000005,-AFalse,-N000000,-AA,-A,-N000,-N000,-N000,-A,-A,-LFalse,-A,-A000000,-A000000,-A,-LFalse,-N00,-LF,-ASRG,-A,-AA