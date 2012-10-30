#!/usr/bin/perl

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

use Cwd 'abs_path','chdir';
use File::Basename;
use lib (fileparse(abs_path($0), qr/\.[^.]*/))[1]."./our_perl_lib/lib";
use DBI;
use Data::Dumper;
$Data::Dumper::Sortkeys = 1;
use Log::Log4perl qw(:easy);
Log::Log4perl->easy_init({ level   => $DEBUG,
#                            file    => ">>test.log" 
# 			   layout   => "%d [%5p] (%6P) [%rms] [%M] - %m{chomp}\t%x\n",
			   layout   => "%5p (%6P) %m{chomp}\n",
});
use XML::Simple;
use URI::Escape;
use Mind_work::WikiCommons;
use Mind_work::WikiWork;
LOGDIE "We need the destination path.\n" if ( $#ARGV != 0 );
our $to_path = shift;
$to_path = abs_path("$to_path");

my $attributes_options = {};
my $dbh;
my $ftp_addr = 'http://62.219.96.62/SupportFTP/';
my $attributes = {};
my $customers = {};
my $our_wiki = new WikiWork();

sub write_customer {
    my ($hash) = @_;

    my $tmp = "";
    my $name = $hash->{'displayname'};
    delete $hash->{'displayname'};

    INFO "\tWrite $name info.\t". (WikiCommons::get_time_diff) ."\n";
    my $txt = "=Information=\n\n";

    my $acct_mng = "";
    $acct_mng = $hash->{'Account Manager'} if defined $hash->{'Account Manager'};
    my $sup = "";
    $sup = $hash->{'Support Engineers'} if defined $hash->{'Support Engineers'};
    $sup =~ s/\s*(,|;)\s*/\n\n/g;
    my $prj_mng = "";
    $prj_mng = $hash->{'Project Manager'} if defined $hash->{'Project Manager'};
    my $sup_mng = "";
    $sup_mng = $hash->{'Support Team Manager'} if defined $hash->{'Support Team Manager'};

    $txt .= "{| class=\"wikitable\"
! Account Manager
! Project Manager
! Support Team Manager
! Support Engineers
|-
| $acct_mng
| $prj_mng
| $sup_mng
| $sup
|}\n\n\n";
    delete $hash->{'Account Manager'};
    delete $hash->{'Project Manager'};
    delete $hash->{'Support Team Manager'};
    delete $hash->{'Support Engineers'};

    $txt .= "Customer full name: '''$hash->{name}'''\n\n";
    delete $hash->{'name'};

    $txt .= "Latest installed version is $hash->{'Latest Version'}" if defined $hash->{'Latest Version'};
    $txt .= " and was updated at $hash->{'Last Update Version'}" if defined $hash->{'Last Update Version'};
    $txt .= " by $hash->{'Update By'}." if defined $hash->{'Update By'};
    $txt .= "\n\n";
    delete $hash->{'Latest Version'};
    delete $hash->{'Last Update Version'};
    delete $hash->{'Update By'};

    if (defined $hash->{'System Description Document'} ){
	$tmp = uri_escape( $hash->{'System Description Document'},"^A-Za-z\/:0-9\-\._~%" );
	$txt .= "[$tmp System Description Document]\n\n";
    }
    delete $hash->{'System Description Document'};

    $tmp = "missing";
    if (defined $hash->{'Last Plug Information'} ){
	$tmp = uri_escape( $hash->{'Last Plug Information'},"^A-Za-z\/:0-9\-\._~%" );
	$tmp = "[$tmp here]";
    }
    $txt .= "Last Plug Information is $tmp and was last updated on $hash->{'Last Plug Update'}.\n\n" if defined $hash->{'Last Plug Update'};
    delete $hash->{'Last Plug Information'};
    delete $hash->{'Last Plug Update'};

    $txt .= "DBA service: $hash->{'DBA service'}\n\n" if defined $hash->{'DBA service'};
    $txt .= "Database Type: $hash->{'Database Type'}\n\n" if defined $hash->{'Database Type'};
    if (defined $hash->{'Vendor Network Elements'}) {
	$tmp = $hash->{'Vendor Network Elements'};
	$tmp =~ s/\n/\n:/gm;
	$txt .= "Vendor Network Elements: \n:$tmp\n\n";
    }
    $txt .= "VoIP Customers: $hash->{'VoIP Customers'}\n\n" if defined $hash->{'VoIP Customers'};
    $txt .= "Additional activities: $hash->{'Additional activities'}\n\n" if defined $hash->{'Additional activities'};
    $txt .= "Other agreed services: $hash->{'Other agreed services'}\n\n" if defined $hash->{'Other agreed services'};
    my $q=0 if defined $hash->{'Other agreed services'};
    delete $hash->{'DBA service'};
    delete $hash->{'Database Type'};
    delete $hash->{'Vendor Network Elements'};
    delete $hash->{'VoIP Customers'};
    delete $hash->{'Additional activities'};
    delete $hash->{'Other agreed services'};

    $txt .= "\n\n[[Category:MIND_Customers]]\n";

    delete $hash->{'customer_id'};

    LOGDIE "Leftovers:".Dumper($hash) if scalar (keys %$hash) && $name ne "VStar";
    $our_wiki->wiki_delete_page("Category:$name") if ( $our_wiki->wiki_exists_page("Category:$name") );
    $our_wiki->wiki_edit_page("Category:$name", $txt);
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
    $info->{$_} = $customers->{$code}->{$_} foreach (keys %{$customers->{$code}});
    return $info;
}

$ENV{NLS_LANG} = 'AMERICAN_AMERICA.AL32UTF8';

$dbh=DBI->connect("dbi:Oracle:host=10.0.10.92;sid=BILL", "service25", "service25")|| die( $DBI::errstr . "\n" );
$dbh->{AutoCommit}    = 0;
$dbh->{RaiseError}    = 1;
$dbh->{ora_check_sql} = 1;
$dbh->{RowCacheSize}  = 0;
$dbh->{LongReadLen} = 1024 * 1024;
$dbh->{LongTruncOk}   = 0;

    my $SEL_INFO = "select unique a.rcustcompanycode, a.rcustcompanyname, a.rcustiddisplay
  from tblcustomers a, tblsuppdept b, tbldeptsforcustomers c
 where a.rcustcompanycode = c.rdeptcustcompanycode
   and b.rsuppdeptcode = c.rdeptcustdeptcode
   and c.rcuststatus = 'A'
   and a.rcuststatus = 'A'
   and b.rsuppdeptstatus = 'A'
   and (a.rcustlastscno > 10 or (a.rcustiddisplay='Pelephone' and a.rcustiddisplay='Eastlink'))
   order by a.rcustiddisplay";

my $sth = $dbh->prepare($SEL_INFO);
$sth->execute();

get_attributes_options();
get_attributes();
my $q = {};

while ( my @row=$sth->fetchrow_array() ) {
    my $id = $row[0];
    LOGDIE "Already have this id for cust.\n" if exists $customers->{$id};
    $customers->{$id}->{'name'} = $row[1];
    $customers->{$id}->{'displayname'} = $row[2];
    $q->{"nr".$id}->{'name'} = $row[1];
    $q->{"nr".$id}->{'displayname'} = $row[2];
    ## costi needs
    next if $customers->{$id}->{'name'} eq "Pelephone";

    my $cust_info = get_customer_attributes($row[0]);
    write_customer ($cust_info);
}

$dbh->disconnect if defined($dbh);

WikiCommons::hash_to_xmlfile( $q, "$to_path/customers.xml", "customers" );

INFO "Done.\n";
