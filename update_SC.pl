#!/usr/bin/perl -w
#LD_LIBRARY_PATH=./instantclient_11_2/ perl ./oracle.pl
use warnings;
use strict;

$SIG{__WARN__} = sub { die @_ };
$| = 1;

my @crt_timeData = localtime(time);
foreach (@crt_timeData) {$_ = "0$_" if($_<10);}
print "Start: ". ($crt_timeData[5]+1900) ."-".($crt_timeData[4]+1)."-$crt_timeData[3] $crt_timeData[2]:$crt_timeData[1]:$crt_timeData[0].\n";

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
use Net::FTP;
use File::Path qw(make_path remove_tree);
use Data::Dumper;
$Data::Dumper::Sortkeys = 1;

my $path_prefix = (fileparse(abs_path($0), qr/\.[^.]*/))[1]."";
use Log::Log4perl qw(:easy);
Log::Log4perl->init("$path_prefix/log4perl.config");

use File::Listing qw(parse_dir);
use File::Find;
use File::Copy;
use XML::Simple;
use Encode;
use URI::Escape;
use Data::Compare;
use Storable qw(dclone);
use Mind_work::WikiCommons;

LOGDIE "We need the temp path, the destination path and sc type:b1, b2, f, i, h, r, d, e, g, s, t, k, z, a, p, cancel.\n" if ( $#ARGV != 2 );
our ($tmp_path, $to_path, $sc_type) = @ARGV;

LOGDIE "sc type should be:b1, b2, f, i, h, r, d, e, g, s, t, k, z, a, p, cancel.\n" if $sc_type !~ m/(^[fihrdtkzapseg]$)|(^b[12]$)|(^cancel$)/i;
$sc_type = uc $sc_type;

remove_tree("$tmp_path");
WikiCommons::makedir ("$tmp_path", 1);
WikiCommons::makedir ("$to_path", 1);
$tmp_path = abs_path("$tmp_path");
$to_path = abs_path("$to_path");
# my $path_prefix = (fileparse(abs_path($0), qr/\.[^.]*/))[1]."";
WikiCommons::set_real_path($path_prefix);

my $sc_table = "mind_sc_ids_versions";
our $svn_pass = 'svncheckout';
our $svn_user = 'svncheckout';
our $general_template_file = "$path_prefix/SC_template.txt";
my $force_db_update = "no";
my ($crt_hash, $failed, $index_comm, $info_comm, $index, $SEL_INFO);

my $ppt_local_files_prefix="/media/wiki_files/ppt_as_flash/";
my $ppt_apache_files_prefix="10.0.0.99/ppt_as_flash/";

LOGDIE "Template file missing.\n" if ! -e $general_template_file;

my $svn_info_all = {};
my $url_sep = WikiCommons::get_urlsep;
my $count_updated = 0;
my $nr_threads = 30;

our ($dbh, $dbh_mysql);

our @doc_types = (
'Market document', 'Market review document',
'Definition document', 'Definition review document',
'HLD document', 'HLD review docuemnt',
'Feature review document',
'HLS Document',
'LLD document', 'LLD review document',
'Architecture document', 'Architecture review document',
'GUI review document',
'Test document',
'STP document'
);


sub write_rtf {
    my ($name, $data) = @_;
    $data =~ s/(^\s+)|(\s+$)//;
    $data =~ s/\$\$\@\@/\'/gs;
    if (! defined $data || $data eq "") {
	unlink "$name" || LOGDIE "Could not delete rtf file: $name.\n";
	return;
    }
    write_file("$name", $data);
}

sub write_file {
    my ($name, $txt) = @_;
    WikiCommons::write_file("$name", Encode::encode('utf8', $txt) );
}

sub fix_sc_text {
  my $text = shift;
#   $text =~ s/\r?\n/ <br\/>\n/g;
  $text =~ s/\r?\n/ \n/g;
#   $text =~ s/^(\*|\#|\;|\:|\=|\!|\||----|\{\|)/<nowiki>$1<\/nowiki>/gm;
  $text =~ s/\$\$\@\@/\'/gs;
#   $text =~ s/\b([a-z][0-9]{4,})/[[SC:$1|$1]]/gmi;
  return "<source lang=\"text\" enclose=\"div\">".$text."</source>";
}

sub general_info {
    my ($info, $index, $modules, $tester, $initiator, $dealer) = @_;

    my $sth = $dbh->prepare("select nvl(wm_concat(distinct(p.affectedFeatures)), ' ') from scproggroups p where changeid=:CHANGEID group by changeid");
    $sth->bind_param( ":CHANGEID", @$info[$index->{'changeid'}] );
    $sth->execute();
    my $affectedFeatures = $sth->fetchrow_array();
    $affectedFeatures = " " if ! defined $affectedFeatures;
# INFO Dumper($affectedFeatures); exit 1;

    local( $/, *FH ) ;
    open(FH, "$general_template_file") or LOGDIE "Can't open file for read: $!.\n";
    my $general = <FH>;
    close(FH);
    my @categories = ();
    $general =~ s/%title%/@$info[$index->{'title'}]/;
    my $tmp = join ' ', @$initiator;
    $general =~ s/%initiator%/$tmp/g;
    $tmp = join ' ', @$dealer;
    $general =~ s/%dealer%/\'\'\'Dealer\'\'\': $tmp/g;
    $general =~ s/%creation_date%/\'\'\'Creation date\'\'\': @$info[$index->{'writtendatetime'}]/g;
    $general =~ s/%modification_date%/\'\'\'Modification date\'\'\': @$info[$index->{'modification_time'}]/g;
    $tmp = "";
    foreach (@$tester) {
	s/\ /_/g;
	$tmp .= "[mailto:$_\@mindcti.com $_]\n";
    }
    $general =~ s/%tester%/$tmp/g;
    $tmp = @$info[$index->{'customer'}];
    my @all_custs = split /,|;|\.|\\/, @$info[$index->{'customer'}];

    my $final_cust = "";
    foreach my $cust (@all_custs) {
	$cust =~ s/B08535//;
	$cust =~ s/B08571//;
	next if $cust =~ m/^\s*$/;
	$cust =~ s/(^\s*)|(\s*$)//g;
	my $corr_cust = WikiCommons::get_correct_customer( $cust );
	if (defined $corr_cust) {
	    $cust = $corr_cust;
	    push @categories, "customer $cust";
	}
	if ($cust !~ m/^\s*[.,:;-_=]\s*All\s*$/i && defined $corr_cust ) {
	  $final_cust = $cust;
	  $cust = "\[\[:Category:$cust\|$cust\]\]";
	}
    }

    if (scalar @all_custs){
	$tmp = join ' ', @all_custs;
	$general =~ s/%customer%/\'\'\'Customer\'\'\': $tmp/;
    } else {
	$general =~ s/%customer%//;
    }

    if (@$info[$index->{'customer_bug'}] eq 'Y' || @$info[$index->{'crmid'}] !~ m/^\s*$/) {
# 	$tmp = @$info[$index->{'crmid'}];
	my @bug_ids = split /,|;/, @$info[$index->{'crmid'}];
	$tmp = "";
	foreach my $bug (@bug_ids) {
	    $bug =~ s/(MIND-(SR#|SR))\s*:?\s*//gi;
	    $bug =~ s/\s+(SR#|SR)\s+(No\.\s+)?//gi;
	    $bug =~ s/^(SR#|SR)\s+(No\.\s+)?//gi;
	    $bug =~ s/\s+/ /g;
	    $bug =~ s/(^\s+)|(\s+$)//g;
	    if ($bug =~ m/^\s*([^\/\\]*)(\/|\\)\s*([0-9]{1,})\s*$/ && $final_cust !~ m/All/i && $final_cust !~ m/^\s*$/ ){
		my $q = $1;
		my $w = $3;
		$q =~ s/^\s*SR\s*$//i;
		$q =~ s/\s+SR\s*$//i;
		if ($q eq "" ){
		    $tmp .= " [[CRM:$final_cust$url_sep$w]]";
		} else {
		    LOGDIE "Strange crmid: $bug with $q == $w.\n" if ! defined $w || $w eq "";
		    my $qq = WikiCommons::get_correct_customer( $q );
		    if (defined $qq) {
			$tmp .= " [[CRM:$qq$url_sep$w]]";
		    } else {
			$tmp .= " $q$url_sep$w";
		    }
		}
	    } elsif ($bug =~ m/^\s*([0-9]{1,})\s*$/ && $final_cust !~ m/^\s*$/ && $final_cust !~ m/All/i){
		$tmp .= " [[CRM:$final_cust$url_sep$1]]";
	    } else {
		$tmp .= " $bug";
	    }
	}
	$general =~ s/%customer_bug%/\'\'\'Customer bug\'\'\' (CRM ID): $tmp/;
    } else {
# INFO "@$info[$index->{'customer_bug'}]   @$info[$index->{'crmid'}]\n";
	$general =~ s/%customer_bug%//;
    }
    $general =~ s/%type%/@$info[$index->{'changetype'}]/;
    push @categories, "ChangeType ".@$info[$index->{'changetype'}];
    $general =~ s/%category%/@$info[$index->{'category'}]/;
    $general =~ s/%project%/@$info[$index->{'projectname'}]/;
    $general =~ s/%product%/@$info[$index->{'productname'}]/;
    $general =~ s/%full_status%/@$info[$index->{'fullstatus'}]/;
    $general =~ s/%status%/@$info[$index->{'status'}]/;
    if (@$info[$index->{'deployment'}] eq "Y") {
	$tmp = "Y => [[SC Deployment:@$info[$index->{'changeid'}]|here]]" 
    } else {
	$tmp = "N";
    }
    $general =~ s/%has_deployment%/$tmp/;

    if (@$info[$index->{'cancel_remark'}] !~ m/^\s*$/) {
#       $tmp = @$info[$index->{'cancel_remark'}];
#       $tmp =~ s/\b([a-z][0-9]{4,})/[[SC:$1|$1]]/gi;
      $tmp = fix_sc_text(@$info[$index->{'cancel_remark'}]);
      $general =~ s/%cancel_reason%/\'\'\'Cancel remark\'\'\': $tmp/;
    } else {
      $general =~ s/%cancel_reason%\n//;
    }

    if (@$info[$index->{'suspend_remark'}] !~ m/^\s*$/) {
#       $tmp = @$info[$index->{'suspend_remark'}];
#       $tmp =~ s/\b([a-z][0-9]{4,})/[[SC:$1|$1]]/gi;
      $tmp = fix_sc_text(@$info[$index->{'suspend_remark'}]);
      $general =~ s/%suspend_reason%/\'\'\'Suspend remark\'\'\': $tmp/;
    } else {
      $general =~ s/%suspend_reason%\n//;
    }

    if (@$info[$index->{'fixesdescription'}] ne '' && @$info[$index->{'fixesdescription'}] ne ' ') {
# 	$tmp = @$info[$index->{'fixesdescription'}];
# 	$tmp =~ s/\r?\n/ <br\/>\n/g;
# 	$tmp =~ s/^(\*|\#|\;|\:|\=|\!|\||----|\{\|)/<nowiki>$1<\/nowiki>/gm;
# 	$tmp =~ s/\$\$\@\@/\'/gs;
# 	$tmp =~ s/\b([a-z][0-9]{4,})/[[SC:$1|$1]]/gmi;
	$tmp = fix_sc_text(@$info[$index->{'fixesdescription'}]);
	$general =~ s/%fix_description%/\'\'\'Fix description\'\'\':\n\n$tmp/;
    } else {
	$general =~ s/%fix_description%//;
    }

    if ($affectedFeatures !~ m/^\s*$/) {
	$tmp = fix_sc_text($affectedFeatures);
	$general =~ s/%affectedFeatures%/\'\'\'Affected Features & Parameters\'\'\':\n\n$tmp/;
    } else {
	$general =~ s/%affectedFeatures%//;
    }

    my $test_remarks = "";

    if (@$info[$index->{'needs test_remark'}] !~ m/^\s*$/) {
      $tmp = fix_sc_text(@$info[$index->{'needs test_remark'}]);
      $test_remarks .= "<li>\'\'\'Needs test remark\'\'\':\n\n$tmp</li>";
#       $general =~ s/%needs_test_remark%/\'\'\'Needs test remark\'\'\':\n\n$tmp/;
    } 
# else {
#       $general =~ s/%needs_test_remark%\n//;
#     }
    if (@$info[$index->{'incharge test_remark'}] !~ m/^\s*$/) {
      $tmp = fix_sc_text(@$info[$index->{'incharge test_remark'}]);
      $test_remarks .= "<li>\'\'\'Incharge test remark\'\'\':\n\n$tmp</li>";
#       $general =~ s/%incharge_test_remark%/\'\'\'Incharge test remark\'\'\':\n\n$tmp/;
    }
#  else {
#       $general =~ s/%incharge_test_remark%\n//;
#     }
    if (@$info[$index->{'approve test_remark'}] !~ m/^\s*$/) {
      $tmp = fix_sc_text(@$info[$index->{'approve test_remark'}]);
      $test_remarks .= "<li>\'\'\'Approve test remark\'\'\':\n\n$tmp</li>";
#       $general =~ s/%approve_test_remark%/\'\'\'Approve test remark\'\'\':\n\n$tmp/;
    }
#  else {
#       $general =~ s/%approve_test_remark%\n//;
#     }
#     if (@$info[$index->{'needs test_remark'}] =~ m/^\s*$/ && @$info[$index->{'incharge test_remark'}] =~ m/^\s*$/ && @$info[$index->{'approve test_remark'}] =~ m/^\s*$/) {
#       $general =~ s/\'\'\'Test remarks\'\'\':\n//;
#     }
    if ($test_remarks ne "") {
	$general =~ s/%testRemarks%/\'\'\'Test remarks\'\'\':\n<ul>$test_remarks<\/ul>/;
    } else {
	$general =~ s/%testRemarks%//;
    }

    $general =~ s/%fix_version%/@$info[$index->{'fixversion'}]/g;
#     $tmp = @$info[$index->{'fixversion'}];
#     $tmp =~ s/(^\s*)|(\s*$)//;
#     if ($tmp && $tmp ne '' && $tmp !~ m/[a-z ]/i){
# 	$tmp =~ s/\(.*?\)//i;
# 	$tmp =~ s/\+$//i;
# 	my ($main, $ver, $ver_fixed, $big_ver, $ver_sp, $ver_without_sp) = WikiCommons::check_vers($tmp, $tmp);
# 	$general =~ s/%fix_version%/[[:Category:$ver_fixed|$ver_fixed]]/g;
#     } else {
# 	$general =~ s/%fix_version%//g;
#     }

    push @categories, "version ". @$info[$index->{'buildversion'}];
    $general =~ s/%version%/@$info[$index->{'version'}]/;
    $general =~ s/%build_version%/@$info[$index->{'buildversion'}]/;
    $general =~ s/%prod_version%/@$info[$index->{'prodversion'}]/;
    $general =~ s/%parent_id%/SC:@$info[$index->{'parent_change_id'}]\|@$info[$index->{'parent_change_id'}]/;
    my $related_tasks = "";
    my @related = split ',', @$info[$index->{'relatedtasks'}];
    for (my $i=0; $i<@related; $i++){
	my $task = $related[$i];
	$task =~ s/(^\s*)|(\s*$)//g;

	next if ($task eq @$info[$index->{'changeid'}] || $task eq '' || $task eq ' ');
	if ($i%6 != 0){
	    $related_tasks .= "| '''[[SC:$task|$task]]'''\n";
	} else {
	    $related_tasks .= "|-\n| '''[[SC:$task|$task]]'''\n";
	}
    }
    if ($related_tasks ne ' ' && $related_tasks ne ''){
	$general =~ s/%related_tasks%/$related_tasks/;
    } else {
	$general =~ s/%related_tasks%/\|none/;
    }
    $tmp = join " <br/>\n", @$modules;
    $general =~ s/%modules%/$tmp/;
    $tmp = join " <br/>\n", (split /\r\n/, @$info[$index->{'moduleslist'}]);
    $general =~ s/%modules_list%/$tmp/;

    $general =~ s/\n{3,}/\n\n\n/gm;
    push @categories, "has_deployment ". @$info[$index->{'deployment'}] if @$info[$index->{'deployment'}] eq "Y";
# INFO Dumper(@$info[$index->{'deployment'}]);
    return ($general, \@categories);
}

sub get_hotfixes {
    my $change_id = shift;

    my $SEL_INFO = "
select to_char(a.request_date, 'yyyy-mm-dd hh:mi:ss '),
       nvl(to_char(a.request_due_date, 'yyyy-mm-dd hh:mi:ss '),' '),
       f.description          status,
       a.priority,
       nvl(a.release_path, ' '),
       nvl(g.fix_explanation, ' '),
       nvl(g.deploy_consideration, ' '),
       nvl(a.cm_remark, ' '),
       nvl(a.ps_remark, ' '),
       nvl(a.rd_remark, ' '),
       nvl(a.test_remark, ' '),
       d.productname,
       c.projectname,
       b.version,
       b.service_pack,
       e.name                 customer,
       a.ps_requester,
       a.ps_poc,
       a.tester,
       a.test_incharge,
       to_char(a.modification_time, 'yyyy-mm-dd hh:mi:ss ')       
  from sc_hot_fixes        a,
       sc_build_manager    b,
       scprojects          c,
       scprods             d,
       sccustomers         e,
       sc_hot_fix_status   f,
       sc_hot_fix_messages g
 where a.change_id = :CHANGEID
   and b.id = a.version_id
   and d.productid = b.product
   and c.projectcode = b.projectcode
   and a.customer = e.id
   and f.id = a.status
   and g.hotfix_id = a.id";

    my $hf_template = "<li>'''#projectname#-#d.productname# #b.version# #b.service_pack# - (#version_bla#) for #e.name#''' : #a.release_path#

{| class=\"wikitable\"
|-
! Status !! Priority !! Request date !! Due date !! PS info !! Testers info
|-
| #f.description# || #a.priority# || #a.request_date# || #a.request_due_date# || #a.ps_requester# <br>POC: #a.ps_poc# || #a.tester# <br>#a.test_incharge#
|}";

    my $hf_crc = '';
    my $txt = '';
    my $sth = $dbh->prepare($SEL_INFO);
    $sth->bind_param( ":CHANGEID", $change_id );
    $sth->execute();
    while ( my @row=$sth->fetchrow_array() ) {
	chomp @row;
	s{^\s+|\s+$}{}g foreach @row;
	my $ver_bla = $row[13];
	$ver_bla =~ s/^([0-9]+\.[0-9]+).*$/$1/;
	$hf_crc .= $row[20];
	my $hf_header = $hf_template;
	$hf_header =~s/#projectname#/$row[11]/;
	$hf_header =~s/#d.productname#/$row[12]/;
	$hf_header =~s/#b.version#/$row[13]/;
	$hf_header =~s/#b.service_pack#/$row[14]/;
	$hf_header =~s/#version_bla#/$ver_bla\/V$ver_bla/;
	$hf_header =~s/#e.name#/$row[15]/;
	if ($row[4] ne '') {
	    $hf_header =~s/#a.release_path#/\[$row[4] Release path is here\]/;
	} else {
	    $hf_header =~s/#a.release_path#//;
	}
	$hf_header =~s/#f.description#/$row[2]/;
	$hf_header =~s/#a.priority#/$row[3]/;
	$hf_header =~s/#a.request_date#/$row[0]/;
	$hf_header =~s/#a.request_due_date#/$row[1]/;
	my ($ps_req, $ps_poc, $tester, $test_ncharge) = (sql_get_workers_names($row[16]), sql_get_workers_names($row[17]), sql_get_workers_names($row[18]), sql_get_workers_names($row[19]));
	$hf_header =~s/#a.ps_requester#/$ps_req->[0]/;
	$hf_header =~s/#a.ps_poc#/$ps_poc->[0]/;
	$hf_header =~s/#a.tester#/$tester->[0]/;
	$hf_header =~s/#a.test_incharge#/$test_ncharge->[0]/;
	my $remarks = "";
	$remarks .= "&mdash; CM remark: $row[7]<br>\n" if $row[7] ne '';
	$remarks .= "&mdash; PS remark: $row[8]<br>\n" if $row[8] ne '';
	$remarks .= "&mdash; R&D remark: $row[9]<br>\n" if $row[9] ne '';
	$remarks .= "&mdash; Test remark: $row[10]<br>\n" if $row[10] ne '';

	$hf_header .= "\n\n$remarks" if $hf_header ne '';

	$hf_header .= "\n\nFix explanation:\n".fix_sc_text($row[5]) if $row[5] ne '';
	$hf_header .= "\n\nDeployment consideration:\n".fix_sc_text($row[6]) if $row[6] ne '';
	$hf_header .= "\n\n\n</li>";
	$txt .= $hf_header;
    }
    my $full_txt = '';
    $full_txt = "=Hot fixes=\n<ul>$txt</ul>" if $txt !~ m/^\s*$/;
    return ($full_txt, $hf_crc);
}

sub sql_get_common_info {
# 	'STP_document'		=> 'svn.parametervalue || svn_doc.parametervalue || \'/Documents/\' ||        prj.svn_path || stp.folder || \'/\'',
    my $hash_fields = {
	'FTP_IP'		=> 'jip.parametervalue',
	'FTP_USER'		=> 'ju.parametervalue',
	'FTP_PASS'		=> 'jp.parametervalue',
	'FTP_market_attach'	=> '\'/SC/\' || kma.parametervalue',
	'FTP_def_attach'	=> '\'/SC/\' || kda.parametervalue',
	'FTP_test_attach'	=> '\'/SC/\' || kdt.parametervalue'
	};


    my $SEL_INFO = "
  from scprojects prj,
	(select *
          from scparameters
         where section = 'ftp\'
           and parameterkey = 'IP\') jip,
       (select *
          from scparameters
         where section = 'ftp\'
           and parameterkey = 'Password\') jp,
       (select *
          from scparameters
         where section = 'ftp\'
           and parameterkey = 'User\') ju,
       (select *
          from scparameters
         where section = 'directories\'
           and parameterkey = 'MARKET_ATTACH_PATH\') kma,
       (select *
          from scparameters
         where section = 'directories\'
           and parameterkey = 'DEF_ATTACH_PATH\') kda,
       (select *
          from scparameters
         where section = 'directories\'
           and parameterkey = 'TEST_ATTACH_PATH\') kdt,
       (select parametervalue
          from scparameters
         where section = 'SVN'
           and parameterkey = 'SVN_DOC_REPOS') svn,
       (select parametervalue
          from scparameters
         where section = 'directories'
           and parameterkey = 'MAIN_DOCS_FOLDER') svn_doc
";

    foreach my $doc (@doc_types) {
	my $q = $doc;
	$q =~ s/ /_/g;
	$hash_fields->{$doc} = "svn.parametervalue || svn_doc.parametervalue || \'/Documents/\' || prj.svn_path || $q.folder || \'/\'";
	$SEL_INFO .= ", (select folder from sc_doc_types where description = \'$doc\') $q";
    }

    my %index;
    my @arr_fields = ();
    push @arr_fields, $_ foreach (sort keys %$hash_fields);
    @index{@arr_fields} = (0..$#arr_fields);
    my @select = ();
    for (my $i=0;$i<=$#arr_fields;$i++) {
	push @select , $hash_fields->{$arr_fields[$i]};
    }
    my $select = join ',', @select;
    my $type;
    if ( $sc_type =~ m/b([1-5])/i ) {
	$type = "B";
    } elsif ($sc_type =~ m/cancel/i) {
	$type = "B"
    } else {
	$type = $sc_type;
    }

    $SEL_INFO = "select $select" . $SEL_INFO . " where prj.projectcode = \'$type\'";
# INFO Dumper($SEL_INFO);exit 1;
    my @info = ();
    my $sth = $dbh->prepare($SEL_INFO);
    $sth->execute();
    my $nr=0;
    while ( my @row=$sth->fetchrow_array() ) {
	LOGDIE "too many rows\n" if $nr++;
	@info = @row;
	chomp @info;
    }
    return \%index, \@info;
}

sub sql_generate_select_changeinfo {
    my $hash_fields = {
	'writtendatetime'	=> 'to_char(a.writtendatetime,\'yyyy-mm-dd hh:mi:ss\')',
	'modification_time'	=> 'nvl(to_char((select max(log_time) from sc_log where change_id=:CHANGEID),\'yyyy-mm-dd hh:mi:ss\'), \' \')',
	'changeid'		=> 'a.changeid',
	'modules'		=> 'nvl(a.modules,\' \')',
	'moduleslist'		=> 'nvl(ml.modules_list,\' \')',
	'buildversion'		=> 'nvl(a.buildversion,\' \')',
	'prodversion'		=> 'nvl(a.prodversion,\' \')',
	'version'		=> 'nvl(a.version,\' \')',
	'status' 		=> 'nvl(a.status,\' \')',
	'fullstatus'		=> 'nvl(a.fullstatus,\' \')',
	'clone' 		=> 'nvl(g.clone,\' \')',
	'projectname'		=> 'p.projectname',
	'productname'		=> 'c.productname',
	'changetype' 		=> 'nvl(a.changetype,\' \')',
	'title'			=> 'nvl(a.title,\' \')',
	'customer_bug'		=> 'nvl(a.is_customer_bug,\' \')',
# 	'customer'		=> 'nvl(a.customer,\' \')',
	'customer'		=> 'nvl(b.name, \' \')',
	'crmid'			=> 'nvl(a.requestref,\' \')',
	'category'		=> 'g.description',
	'fixversion'		=> 'nvl(a.fixversion,\' \')',
	'parent_change_id'	=> 'nvl(a.parent_change_id,\' \')',
	'relatedtasks'		=> 'nvl(a.relatedtasks,\' \')',
	'initiator'		=> 'a.initiator',
	'tester'		=> 'nvl(a.testincharge,-1)',
	'dealer'		=> 'nvl(a.dealer,-1)',
	'deployment'		=> 'nvl(a.DEPLOYMENTCONSIDERATION,\'N\')',
## texts:
	'Market_SC'		=> 'nvl(mi.marketinfo,\' \')',
	'HLS_SC'		=> 'nvl(hl.hlsinfo,\' \')',
	'Description_SC'	=> 'nvl(f.function,\' \')',
	'cancel_remark'		=> 'nvl(a.cancelinformremark,\' \')',
	'suspend_remark'	=> 'nvl(a.SUSPENDINFORMREMARK,\' \')',
	'needs test_remark'	=> 'nvl(a.NEEDS_TEST_REMARK,\' \')',
	'Architecture_SC'	=> 'nvl(am.architecture_memo,\' \')',
	'HLD_SC'		=> 'nvl(hm.hld_memo,\' \')',
	'fixesdescription'	=> 'nvl(fd.fixesdescription,\' \')',
	'incharge test_remark'	=> 'nvl(a.TESTINCHARGEREMARK,\' \')',
	'approve test_remark'	=> 'nvl(a.TESTREMARK,\' \')',
	'Messages_SC'		=> 'nvl(m.messages,\' \')',
	};

    my %index;
    my @arr_fields = ();
    push @arr_fields, $_ foreach (sort keys %$hash_fields);
    @index{@arr_fields} = (0..$#arr_fields);
    my @select = ();
    for (my $i=0;$i<=$#arr_fields;$i++) {
	push @select , $hash_fields->{$arr_fields[$i]};
    }

    my $select = join ',', @select;

    my $SEL_INFO = "
    select $select
    from SCCHANGE           a,
       sccustomers          b,
       SCPRODS              c,
       SCPROJECTS           p,
       SC_CATEGORIES        g,
       SC_MODULES_LIST      ml,
       SC_FIXES_DESCRIPTION fd,
       SC_MESSAGES          m,
       SC_MARKETINFO        mi,
       SC_HLD_MEMO          hm,
       SC_FUNCTION          f,
       SC_ARCHITECTURE_MEMO am,
       sc_hlsinfo	    hl
    where a.changeid = :CHANGEID
      and a.customer_id = b.id(+)
      and a.projectcode = c.projectcode
      and c.productid = a.product
      and p.projectcode = a.projectcode
      and g.id = a.category_id
      and ml.changeid(+) = a.changeid
      and fd.changeid(+) = a.changeid
      and m.changeid(+) = a.changeid
      and mi.changeid(+) = a.changeid
      and hm.changeid(+) = a.changeid
      and f.changeid(+) = a.changeid
      and hl.changeid(+) = a.changeid
      and am.changeid(+) = a.changeid";

    return \%index, $SEL_INFO;
}


sub sql_get_changeinfo {
    my ($change_id, $SEL_INFO) = @_;
    my @info = ();
    my $sth = $dbh->prepare($SEL_INFO);
    $sth->bind_param( ":CHANGEID", $change_id );
    $sth->execute();
    my $nr=0;
    while ( my @row=$sth->fetchrow_array() ) {
	LOGDIE "too many rows\n" if $nr++;
	chomp @row;
	@info = @row;
    }

    return \@info;
}

sub sql_get_workers_names {
    my @ids = @_;
    chomp @ids;
    $_ = '\''.$_.'\'' foreach (@ids);
    my $tmp = join ',', @ids;

    my $SEL_MODULES = "select workername from scwork where id in ( $tmp )";
    my $sth = $dbh->prepare($SEL_MODULES);
    $sth->execute();
    my @workers = ();
    while ( my @row=$sth->fetchrow_array() ) {
	push @workers, @row;
    }
    return \@workers;
}

sub sql_get_dealer_names {
    my @ids = shift;
    chomp @ids;
    $_ = '\''.$_.'\'' foreach (@ids);
    my $tmp = join ',', @ids;

    my $SEL_MODULES = "select name from scdealer where id in ( $tmp )";
    my $sth = $dbh->prepare($SEL_MODULES);
    $sth->execute();
    my @dealers = ();
    while ( my @row=$sth->fetchrow_array() ) {
	push @dealers, @row;
    }
    return \@dealers;
}

sub sql_get_all_changes {
    INFO "-Get all db changes.\n";
    my $cond = "";
    my $ver = "(version >= '5.0' or (nvl(version, 1) < '5.0' and nvl(fixversion,6) > '5.0')) and version <= \'7.0\'";
    if ($sc_type eq 'B2') {
	$ver = "version > \'7.0\'";
# 	$ver = "version >= \'5.0\' and version < \'5.3\'";
#     } elsif ($sc_type eq 'B2') {
# 	$ver = "version >= \'5.3\' and version < \'6.0\'";
#     } elsif ($sc_type eq 'B3') {
# 	$ver = "version >= \'6.0\' and version < \'6.5\'";
#     } elsif ($sc_type eq 'B4') {
# 	$ver = "version >= \'6.5\' and version < \'7.0\'";
#     } elsif ($sc_type eq 'B5') {
# 	$ver = "(version >= \'7.0\' or
# 	(nvl(version, 1) < \'5.0\' and nvl(fixversion, 6) > \'5.0\'))";
    }

    my $no_cancel = "and status <> 'Cancel'
	and status <> 'Inform-Cancel'
	and status <> 'Market-Cancel'";

    if ($sc_type =~ m/B[12]/) {
	$cond = "projectcode = 'B' and $ver";
    } elsif ($sc_type eq 'F') {
	$cond = "projectcode = 'F'";
    } elsif ($sc_type eq 'I') {
	$cond  = "projectcode = 'I' and (nvl(version,5) >= '4.00' or nvl(fixversion,5) >= '4.00')";
    } elsif ($sc_type eq 'H') {
	$cond  = "projectcode = 'H' and writtendatetime > '1Jan2008'";
    } elsif ($sc_type eq 'R') {
	$cond  = "projectcode = 'R'";
    } elsif ($sc_type eq 'E') {
	$cond  = "projectcode = 'E'";
    } elsif ($sc_type eq 'G') {
	$cond  = "projectcode = 'G'";
    } elsif ($sc_type eq 'S') {
	$cond  = "projectcode = 'S'";
    } elsif ($sc_type eq 'T') {
	$cond  = "projectcode = 'T'";
    } elsif ($sc_type eq 'K') {
	$cond  = "projectcode = 'K'";
    } elsif ($sc_type eq 'Z') {
	$cond  = "projectcode = 'Z'";
    } elsif ($sc_type eq 'A') {
	$cond  = "projectcode = 'A'";
    } elsif ($sc_type eq 'P') {
	$cond  = "projectcode = 'P'";
    } elsif ($sc_type eq 'D') {
	$cond  = "projectcode = 'D' and (nvl(version,3) >= '2.30' or nvl(fixversion,3) >= '2.30')";
    } elsif ($sc_type eq 'CANCEL') {
	$cond = "";
	$no_cancel = "(
      (projectcode = 'B' and (version >= '5.0' or (nvl(version, 1) < '5.0' and nvl(fixversion,6) > '5.0')))
       or (projectcode = 'F')
       or (projectcode = 'I' and (nvl(version, 5) >= '4.00' or nvl(fixversion,5) >= '4.00'))
       or (projectcode = 'H' and writtendatetime > '1Jan2008')
       or (projectcode = 'R')
       or (projectcode = 'E')
       or (projectcode = 'G')
       or (projectcode = 'S')
       or (projectcode = 'T')
       or (projectcode = 'K')
       or (projectcode = 'Z')
       or (projectcode = 'A')
       or (projectcode = 'P')
       or (projectcode = 'D' and (nvl(version, 3) >= '2.30' or nvl(fixversion, 3) >= '2.30'))
      ) and (status = 'Cancel' or status = 'Inform-Cancel' or status = 'Market-Cancel')";
    } else {
	LOGDIE "Impossible.\n";
    }

    my $SEL_CHANGES = "select changeid, nvl(crc,0), status, projectcode, nvl(deploymentconsideration, 'N')
	from scchange
	where product is not null and $cond $no_cancel";

    my $sth = $dbh->prepare($SEL_CHANGES);
    $sth->execute();
    my $crt_hash = {};
    while ( my @row=$sth->fetchrow_array() ) {
	$crt_hash->{$row[0]} = \@row;
    }
    INFO "+Get all db changes.\n";
    return $crt_hash;
}

sub sql_get_svn_docs {
    my $change_id = shift;
    my $SEL_DOCS = "
    select docty.description, t.documentname
    from sc_doc_management t,
	sc_doc_types docty,
	scprojects prj,
	(select parametervalue
	    from scparameters
	    where section = \'SVN\'
	    and parameterkey = \'SVN_DOC_REPOS\') svn,
	(select parametervalue
	    from scparameters
	    where section = \'directories\'
	    and parameterkey = \'MAIN_DOCS_FOLDER\') svn_doc
    where t.changeid = :CHANGEID
    and t.documenttype = docty.id
    and prj.projectcode = Substr(:CHANGEID, 1, 1) and docty.description in (";

    my @tmp = ();
    foreach my $doc (@doc_types){
	push @tmp, "\'$doc\'";
    }
    $SEL_DOCS = $SEL_DOCS. (join ',', @tmp) . ")";

    my $sth = $dbh->prepare($SEL_DOCS);
    $sth->bind_param( ":CHANGEID", $change_id);
    $sth->execute();
    my $docs = {};
    while ( my @row=$sth->fetchrow_array() ) {
	LOGDIE "too many rows\n" if $#row>1;
	$docs->{$row[0]} = $row[1];
    }
    return $docs;
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

# sub sql_get_relpath {
#     my $SEL = "select svn.parametervalue
#   from (select parametervalue
#           from scparameters
#          where section = \'SVN\'
#            and parameterkey = \'SVN_DOC_REPOS\') svn";
#     my $sth = $dbh->prepare($SEL);
#     $sth->execute();
#     while ( my @row=$sth->fetchrow_array() ) {
# 	LOGDIE "too many rows\n" if $#row>1;
# 	return $row[0];
#     }
# }

sub get_previous {
    my $change_id = shift;
    my $info_hash = {};
    my $ret = $dbh_mysql->selectrow_array("select FILES_INFO_CRT from $sc_table where SC_ID='$change_id'");
    return $info_hash if ! defined $ret || ! -d "$to_path/$change_id";
    my @info = split "\n", $ret;
    chomp @info;
    foreach my $line (@info) {
	my @all = split(/;/, $line);
	return if (@all < 1);
	$all[0] =~ s/^[0-9]{1,} //;
	$info_hash->{$all[0]}->{'name'} = $all[1];
	$info_hash->{$all[0]}->{'size'} = $all[2];
	$info_hash->{$all[0]}->{'revision'} = $all[3];
	## like this in order to not update everything after we added the date to docs
	$info_hash->{$all[0]}->{'date'} = $all[4] if defined  $all[4];
    }
    return $info_hash;
}
#
# sub ftpconnect {
#     INFO "\t*** Connecting again: $nr_retries.\n" if $nr_retries>=0;
#     $ftp = Net::FTP->new("$ip", Debug => 0, Timeout => 300) or LOGDIE "Cannot connect to some.host.name: $@";
#     $ftp->login("$user","$pass") or LOGDIE "Cannot login ", $ftp->message;
#     $ftp->pasv;
#     $ftp->binary();
#     $nr_retries++;
# }
#
# sub ftp_cmds {
#     my ($change_id, $local_dir, $remote_path) = @_;
#     my $res = $ftp->cwd("$remote_path");
#     my $err = $!;
#     return 'cd '.$err if defined $err && $err ne "";
#     return 'OK' if $res eq "";
#     my @list = $ftp->ls('-lR');
#     $err = $!;
#     return 'ls '.$err if defined $err && $err ne "";
#     my @files = ();
#     foreach my $file (parse_dir(\@list)) {
# 	my ($name, $type, $size, $mtime, $mode) = @$file;
# 	if ($type eq "d") {
# 	    makedir("$local_dir/$name");
# 	} elsif ($type eq "f") {
# 	    push @files, "$name";
# 	} else {
# 	    LOGDIE "Unknown file type : $type for $name at $change_id in $remote_path.\n";
# 	}
#     }
#     foreach my $file (@files) {
# 	INFO "\tGet file $file.\n";
# 	my $res = $ftp->get("$file", "$local_dir/$file");
# 	my $err = $!;
# 	if (!defined $res && $ftp->message =~ m/: The system cannot find the file specified.\s*$/) {
# 	    INFO "\t=== Fucking weird file name: $file\n";
# 	} else {
# 	    return "get $file ".$ftp->message." ".$err if !defined $res || (defined $err && $err ne "");
# 	}
#     }
#     return 'OK';
# }
#
# sub ftp_get {
#     opendir(DIR, "$ftp_tmp_path") || die("Cannot open directory $ftp_tmp_path.\n");
#     my @ids = grep { (!/^\.\.?$/) && -d "$ftp_tmp_path/$_" } readdir(DIR);
#     closedir(DIR);
#
#     my $count = 1;
#
#     INFO "Connect to ftp.\n";
#     our $nr_retries = -1;
#     our $ftp;
#
#
#     ftpconnect;
#     foreach my $change_id (sort @ids){
# 	my $dif = time() - $time;
# 	INFO " ftp for $change_id ".$count++ ." from ". scalar @ids."\t$dif.\n";
# 	foreach my $type ($ftp_uri_def, $ftp_uri_mrkt, $ftp_uri_test) {
# 	    INFO "   ftp for dir $type/$change_id\t$dif.\n";
# 	    my $remote_path = "$type/$change_id/";
# 	    my $local_type = $type; $local_type =~ s/\/$//g;
# 	    my ($name,$dir,$suffix) = fileparse("$local_type", qr/\.[^.]*/);
# 	    my $work_dir = "$ftp_tmp_path/$change_id";
# # 	    my $res = `wget -q -nH --cut-dirs=2 -r -t 3 -T 120 --user=$user --password=$pass -P "$local_dir" ftp://$ip/$remote_path`;
# 	    makedir ("$work_dir/ftp/$name");
# 	    my $status = "";
# 	    while ($status ne "OK") {
# 		$status = ftp_cmds($change_id, "$work_dir/ftp/$name", $remote_path);
# 		if ($status ne "OK") {
# 		    INFO "\t=== Error with message: $status.\n";
# 		    ftpconnect;
# 		}
# 	    }
# 	}
# 	finddepth sub { rmdir ($File::Find::name) if -d ;}, "$ftp_tmp_path/$change_id";
# 	move("$ftp_tmp_path/$change_id", "$result_dir/$change_id");
#     }
#     $ftp->quit;
#     INFO "Disconnect to ftp.\n";
# }

sub write_common_info {
    my ($index_comm, $info_comm) = @_;
    my $text = "";

    foreach my $key (sort keys %$index_comm) {
	$text .= "$key = @$info_comm[$index_comm->{$key}]\n";
    }
    write_file("$to_path/common_info", $text);
}

sub svn_list {
    my ($dir, $file) = @_;
    INFO "\t-SVN list for $file.\n" if defined $file;
    my $res = "";;
    if (exists $svn_info_all->{$dir}) {
	$res = $svn_info_all->{$dir}->{$file};
    } else {
	$dir .= "/$file" if defined $file;
	my $xml = `svn list --xml --non-interactive --no-auth-cache --trust-server-cert --password $svn_pass --username $svn_user \'$dir\' 2> /dev/null`;
	if ($?) {
	    INFO "\tError $? for svn.\n";
	    return undef;
	}
	my $hash = XMLin($xml);
	$res = $hash->{'list'}->{'entry'} if exists $hash->{'list'}->{'entry'};
    }
    INFO "\t+SVN list for $file.\n" if defined $file;
    return $res;
}

sub search_for_presentations {
    my ($change_id) = @_;
    my $local_path = "$ppt_local_files_prefix/$change_id";
    my $control = "";
    my $text = ();
    foreach my $file (sort <$local_path/*>){
	next if $file !~ m/\.swf$/i;
	my ($name, $dir, $suffix) = fileparse($file, qr/\.[^.]*/);
	my $apache_file = "$ppt_apache_files_prefix/$change_id/$name$suffix";
	$apache_file =~ s/\/+/\//g;
	$apache_file = uri_escape( $apache_file,"^A-Za-z\/:0-9\-\._~%" );
	$text .= "
\n<toggledisplay status=\"hide\" showtext=\"$name\" hidetext=\"Close presentation\">
To open the presentation in a new tab, click [http://$apache_file here].
<swf width=\"800\" height=\"500\" >http://$apache_file</swf>
</toggledisplay>\n";
	$control .= $name;
    }
    $control .= "v1.5" if $control ne "";
    return ($text, $control);
}

sub clean_existing_dir {
    my ($change_id, $svn_docs) = @_;
    return if ! -e "$to_path/$change_id";
    opendir(DIR, "$to_path/$change_id") || LOGDIE "Cannot open directory $to_path/$change_id: $!.\n";
    my @files = grep { (!/^\.\.?$/) && -f "$to_path/$change_id/$_" && "$_" =~ /\.doc$/} readdir(DIR);
    closedir(DIR);
    foreach my $file (@files){
	my ($name,$dir,$suffix) = fileparse($file, qr/\.[^.]*/);
	if ( ! exists $svn_docs->{$name}) {
	    INFO "\tDelete file $file because it doesn't exist on svn anymore.\n";
	    unlink("$to_path/$change_id/$file") or LOGDIE "Could not delete the file $file: $!\n" ;
	}
    }
}

sub remove_old_dirs {
    my @scdirs = @_;
    ## remove not needed directories
    opendir(DIR, "$to_path") || LOGDIE "Cannot open directory $to_path: $!.\n";
    my @dirs = grep { (!/^\.\.?$/) && -d "$to_path/$_"} readdir(DIR);
    closedir(DIR);
    my ($only_in_sc, $only_in_dirs, $common) = WikiCommons::array_diff( \@scdirs, \@dirs);
    INFO "Deleting ".(scalar @$only_in_dirs)." old changes.\n";
    foreach my $dir (@$only_in_dirs) {
	INFO "Remove old dir $dir from db.\n";
	my $sth_mysql = $dbh_mysql->do("delete from $sc_table where sc_id='$dir'");
	remove_tree("$to_path/$dir");
    }
}

sub add_versions_to_wiki_db {
    my ($change_id, $info, $index, $hash, $categories) = @_;
    INFO "Update dn info about $change_id.";
    $count_updated++;
    my $text = "";
    for (my $i=0;$i<@doc_types;$i++) {
	next if ! exists $hash->{$doc_types[$i]};
	my $rev = $hash->{$doc_types[$i]}->{'revision'} || '';
	my $name = $hash->{$doc_types[$i]}->{'name'} || '';
	my $date = $hash->{$doc_types[$i]}->{'date'} || '';
	my $size = $hash->{$doc_types[$i]}->{'size'} || '';
# 	$size = $hash->{$doc_types[$i]}->{'size'} if ( defined $hash->{$doc_types[$i]}->{'size'} );
	$text .= (1000 + $i) . " $doc_types[$i];$name;$size;$rev;$date\n";
    }

    $text .= "SC_info;$hash->{'SC_info'}->{'name'};$hash->{'SC_info'}->{'size'};$hash->{'SC_info'}->{'revision'};$hash->{'SC_info'}->{'date'}\n";
    $text .= "Categories;". (join ';',@$categories). "\n" if defined $categories && scalar @$categories;
    my $sth_mysql = $dbh_mysql->prepare("REPLACE INTO $sc_table 
		(SC_ID, FIXVERSION, BUILDVERSION, VERSION, PRODVERSION, FILES_INFO_CRT) 
		VALUES 
		('$change_id', '@$info[$index->{'fixversion'}]', 
		 '@$info[$index->{'buildversion'}]', 
		 '@$info[$index->{'version'}]', 
		 '@$info[$index->{'prodversion'}]', 
		 ".$dbh_mysql->quote($text).")");
    $sth_mysql->execute();
    $sth_mysql->finish();
}

sub get_info_files_md5_crc {
    my $change_id = shift;
    my $crc = WikiCommons::get_file_md5("$to_path/$change_id/General_info.wiki", 1).
    WikiCommons::get_file_md5("$to_path/$change_id/1 Market_SC.rtf", 1).
    WikiCommons::get_file_md5("$to_path/$change_id/2 HLS_SC.rtf", 1).
    WikiCommons::get_file_md5("$to_path/$change_id/3 Description_SC.rtf", 1).
    WikiCommons::get_file_md5("$to_path/$change_id/4 HLD_SC.rtf", 1).
    WikiCommons::get_file_md5("$to_path/$change_id/5 Messages_SC.rtf", 1).
    WikiCommons::get_file_md5("$to_path/$change_id/6 Architecture_SC.rtf", 1);
    return $crc;
}

sub work_svn {
    my ($change_id, $info_comm, $prev_info, $index_comm, $work_dir) = @_;
    my $missing_documents = {};
    my $crt_info = {};
    my $update_control_file = 0;

    my $svn_docs = sql_get_svn_docs($change_id);
    clean_existing_dir($change_id, $svn_docs);

    foreach my $key (sort keys %$svn_docs) {
	my $dir = @$info_comm[$index_comm->{$key}];
	my $file = $svn_docs->{$key};
	my $res = svn_list($dir, $file);

	my $doc_rev = $res->{'commit'}->{'revision'};
	my $doc_size = $res->{'size'};
	if ( ! defined $res || (! defined $doc_rev && ! defined $doc_size)) {
	    INFO "\tSC $change_id says we have document for $key, but we don't have anything on svn.\n";
	    $missing_documents->{$key} = "$dir/$file";
	    next;
	}
	delete $prev_info->{$key} if (!(-e "$to_path/$change_id/$key.doc" && -s "$to_path/$change_id/$key.doc" == $doc_size));
	$crt_info->{$key}->{'name'} = $svn_docs->{$key};
	$crt_info->{$key}->{'size'} = $doc_size;
	$crt_info->{$key}->{'revision'} = $doc_rev;
	$crt_info->{$key}->{'date'} =  $res->{'commit'}->{'date'};
	if ( ! Compare($crt_info->{$key}, $prev_info->{$key}) ) {
	    INFO "\tUpdate svn http for $key.\n";
	    my $file_res = WikiCommons::http_get("$dir/$file", "$work_dir", "$svn_user", "$svn_pass");
	    move($file_res, "$work_dir/$key.doc") || LOGDIE "can't move file $file_res to $work_dir/$key.doc: $!.\n";
	    $update_control_file++;
	}
    }
    return ($missing_documents, $crt_info, $update_control_file);
}

sub mysql_connect {
    ### connect to mysql to use the wikidb
    my ($wikidb_server, $wikidb_name, $wikidb_user, $wikidb_pass) = ();
    open(FH, "/var/www/html/wiki/LocalSettings.php") or LOGDIE "Can't open file for read: $!.\n";
    while (<FH>) {
      $wikidb_server = $2 if $_ =~ m/^(\s*\$wgDBserver\s*=\s*\")(.+)(\"\s*;\s*)$/;
      $wikidb_name = $2 if $_ =~ m/^(\s*\$wgDBname\s*=\s*\")(.+)(\"\s*;\s*)$/;
      $wikidb_user = $2 if $_ =~ m/^(\s*\$wgDBuser\s*=\s*\")(.+)(\"\s*;\s*)$/;
      $wikidb_pass = $2 if $_ =~ m/^(\s*\$wgDBpassword\s*=\s*\")(.+)(\"\s*;\s*)$/;
    }
    close(FH);

    $dbh_mysql = DBI->connect("DBI:mysql:database=$wikidb_name;host=$wikidb_server", "$wikidb_user", "$wikidb_pass");
    $dbh_mysql->{AutoCommit}    = 1;
    $dbh_mysql->{RaiseError}    = 1;
    $dbh_mysql->{RowCacheSize}  = 16;
    $dbh_mysql->{LongReadLen}   = 52428800;
    $dbh_mysql->{LongTruncOk}   = 0;

    my $sth_mysql = $dbh_mysql->prepare("CREATE TABLE IF NOT EXISTS $sc_table (
    SC_ID VARCHAR( 255 ) NOT NULL ,
    FIXVERSION VARCHAR( 255 ) ,
    BUILDVERSION VARCHAR( 255 ) ,
    VERSION VARCHAR( 255 ) ,
    PRODVERSION VARCHAR( 255 ) ,
    FILES_INFO_CRT VARCHAR( 9000 ) ,
    PRIMARY KEY ( SC_ID ) )");
    $sth_mysql->execute();
    $sth_mysql->finish();
}
sub oracle_conenct {
    ### connect to oracle
    $ENV{NLS_LANG} = 'AMERICAN_AMERICA.AL32UTF8';
    my ($ip, $sid, $user, $pass) = ('10.0.0.103', 'SCROM', 'scview', 'scview');
    $dbh=DBI->connect("dbi:Oracle:host=$ip;sid=$sid", "$user", "$pass")|| die( $DBI::errstr . "\n" );
    $dbh->{AutoCommit}    = 1;
    $dbh->{RaiseError}    = 1;
    $dbh->{ora_check_sql} = 0;
    $dbh->{RowCacheSize}  = 16;
    $dbh->{LongReadLen}   = 52428800;
    $dbh->{LongTruncOk}   = 0;
}

# sub clone_dbh {
#   my $handler = shift;
#   my $child_dbh = $handler->clone();
#   $handler->{InactiveDestroy} = 1;
#   undef $handler;
#   return $child_dbh;
# }

sub fork_function {
    my ($nr_threads, $function, @function_args) = @_;
    use POSIX ":sys_wait_h";
    INFO "Start forking.\n";
    my $running;
    my $total_nr = scalar (keys %$crt_hash);
    my $crt_nr = 0;
    my @thread = (1..$nr_threads);
#  Remaining threads: ".(scalar @thread).", running threads: ".(scalar keys %$running)."
    while (1) {
	my $crt_thread = shift @thread if scalar keys %$crt_hash;
	if (defined $crt_thread) {
	    my $change_id = (sort keys %$crt_hash)[0];
# if ($change_id !~ m/F00050/){push @thread, $crt_thread;delete $crt_hash->{$change_id};delete $failed->{$change_id};next;}
	    my $val = $crt_hash->{$change_id};
	    $crt_nr++;
	    INFO "************* Start working in thread nr $crt_thread for $change_id (nr $crt_nr of $total_nr). Free threads: ".(scalar @thread)." out of $nr_threads.\n";
	    my $pid = fork();
	    if (! defined ($pid)){
		LOGDIE  "Can't fork.\n";
	    } elsif ($pid == 0) {
		INFO "Start fork for $change_id.\n";
		$0 = "update_SC $sc_type - $change_id";
		$dbh_mysql->disconnect() if defined($dbh_mysql);mysql_connect();
# 		my $child_dbh_mysql = clone_dbh($dbh_mysql);undef $dbh_mysql;$dbh_mysql=$child_dbh_mysql;
		$dbh->disconnect if defined($dbh);oracle_conenct();
# 		my $child_dbh = clone_dbh($dbh);undef $dbh;$dbh=$child_dbh;
		$function->($change_id, $val, $crt_thread, @function_args);
		$dbh_mysql->disconnect() if defined($dbh_mysql);
		$dbh->disconnect if defined($dbh);
		INFO "Done fork for $change_id.\n";
		exit 255 if $count_updated;
		exit 0;
	    }
	    $running->{$pid}->{'thread'} = $crt_thread;
	    $running->{$pid}->{'change_id'} = $change_id;
	    delete $crt_hash->{$change_id};
	}

	## clean done children
	my $pid = waitpid(-1, WNOHANG);
	my $exit_status = $? >> 8;
	if ($pid > 0) {
	    my $change_id = $running->{$pid}->{'change_id'};
	    push @thread, $running->{$pid}->{'thread'};
	    delete $failed->{$change_id} if $exit_status == 0 || $exit_status == 255;
	    $count_updated++ if $exit_status == 255;
	    delete $running->{$pid};
	    INFO "************* Finish working for $change_id (pid=$pid, status=$exit_status).\n";
	}
	## don't sleep if not all threads are running and we still have work to do
	sleep 1 if !(scalar @thread && scalar keys %$crt_hash);
	## if no threads are working and there is no more work to be done
	last if scalar @thread == $nr_threads && scalar keys %$crt_hash == 0;
    }
}

## problem: after the first run we can have missing documents, but the general_info will not be updated
sub update_scid {
    my ($change_id, $arr) = @_;
    my $work_dir = "$tmp_path/$change_id";
    WikiCommons::makedir($work_dir);
    my $prev_info = get_previous($change_id);
    ### svn updates (first svn, because we need missing documents)
    my ($missing_documents, $crt_info, $update_control_file) = work_svn($change_id, $info_comm, $prev_info, $index_comm, $work_dir);
    my ($presentations, $control) = search_for_presentations($change_id);
    my ($hf_txt, $hf_crc) = get_hotfixes($change_id);

    ## db update
    $crt_info->{'SC_info'}->{'name'} = @$arr[0];
    $crt_info->{'SC_info'}->{'size'} = @$arr[1].$control.(@$arr[4] eq "Y" ? "Y" : "").$hf_crc;
    $crt_info->{'SC_info'}->{'revision'} = @$arr[2];
    $crt_info->{'SC_info'}->{'date'} = "sc_date is not used";

    my $cat = ();
## docs are verified through $update_control_file
    delete $prev_info->{'Categories'};
    if (! Compare($crt_info, $prev_info) || $update_control_file || $force_db_update eq "yes") {
 	INFO "\tUpdate SC info.\n";

	my $prev = defined $prev_info->{'SC_info'}->{'size'} ? $prev_info->{'SC_info'}->{'size'} : 'NULL';
	INFO "\tChanged CRC: $crt_info->{'SC_info'}->{'size'} from $prev.\n" if ( defined $crt_info->{'SC_info'}->{'size'} && "$crt_info->{'SC_info'}->{'size'}" ne "$prev");
	$prev = defined $prev_info->{'SC_info'}->{'revision'} ? $prev_info->{'SC_info'}->{'revision'} : 'NULL';
	INFO "\tChanged status: $crt_info->{'SC_info'}->{'revision'} from $prev.\n" if ( defined $crt_info->{'SC_info'}->{'revision'} && "$crt_info->{'SC_info'}->{'revision'}" ne "$prev");
	INFO "\tChanged svn files.\n" if $update_control_file;

	my $info_ret = sql_get_changeinfo($change_id, $SEL_INFO);
	## some SR's are completly empty, so ignore them
	return if scalar @$info_ret == 0;
	my $modules = sql_get_modules( split ',', @$info_ret[$index->{'modules'}] ) if defined @$info_ret[$index->{'modules'}];
	my $tester = sql_get_workers_names( split ',', @$info_ret[$index->{'tester'}] ) if defined @$info_ret[$index->{'tester'}];
	my $initiator = sql_get_workers_names( split ',', @$info_ret[$index->{'initiator'}] );
	my $dealer = sql_get_dealer_names( split ',', @$info_ret[$index->{'dealer'}] );
	my ($txt, $categories) = general_info($info_ret, $index, $modules, $tester, $initiator, $dealer);

	$cat = $categories;
	foreach my $key (sort keys %$missing_documents) {
	    my $link = $missing_documents->{$key};
	    $link =~ s/\s/%20/g;
	    $txt .= "\nMissing \'\'\'$key\'\'\' from [$link this] svn address, but database says it should exist.\n";
	}
	$txt .= "\n'''Presentations'''\n\nThe following presentations were found for this ".lc(@$info_ret[$index->{'changetype'}])." (either made by Q&A or attached to it):".$presentations if defined $presentations && $presentations ne "";

	my $crt_md5 = get_info_files_md5_crc($change_id);
	write_file ("$work_dir/General_info.wiki" ,$txt."\n$hf_txt\n");
	unlink glob ("$to_path/$change_id/*.rtf"); 
	write_rtf ("$work_dir/1 Market_SC.rtf", @$info_ret[$index->{'Market_SC'}]);
	write_rtf ("$work_dir/2 HLS_SC.rtf", @$info_ret[$index->{'HLS_SC'}]);
	write_rtf ("$work_dir/3 Description_SC.rtf", @$info_ret[$index->{'Description_SC'}]);
	write_rtf ("$work_dir/4 HLD_SC.rtf", @$info_ret[$index->{'HLD_SC'}]);
	write_rtf ("$work_dir/5 Messages_SC.rtf", @$info_ret[$index->{'Messages_SC'}]);
	write_rtf ("$work_dir/6 Architecture_SC.rtf", @$info_ret[$index->{'Architecture_SC'}]);
	my $new_md5 = get_info_files_md5_crc($change_id);
	add_versions_to_wiki_db($change_id, $info_ret, $index, $crt_info, $cat) if $crt_md5 ne $new_md5 || $update_control_file || ! defined $prev_info->{'SC_info'}->{'revision'};
    }
    WikiCommons::move_dir($work_dir, "$to_path/$change_id/");
}

sub cleanAndExit {
    WARN "Killing all child processes\n";
    kill 9, map {s/\s//g; $_} split /\n/, `ps -o pid --no-headers --ppid $$`;
    exit 1000;
}
use sigtrap 'handler' => \&cleanAndExit, 'INT', 'ABRT', 'QUIT', 'TERM';

mysql_connect();
oracle_conenct();
$crt_hash = sql_get_all_changes();
remove_old_dirs(keys %$crt_hash);
$failed = dclone($crt_hash);
($index_comm, $info_comm) = sql_get_common_info();
write_common_info ($index_comm, $info_comm);
($index, $SEL_INFO) = sql_generate_select_changeinfo();
$dbh->disconnect if defined($dbh);
$dbh_mysql->disconnect() if defined($dbh_mysql);

fork_function($nr_threads, \&update_scid);

ERROR "Failed: $_\n" foreach (sort keys %$failed);
@crt_timeData = localtime(time);
foreach (@crt_timeData) {$_ = "0$_" if($_<10);}
INFO "End ". ($crt_timeData[5]+1900) ."-$crt_timeData[4]-$crt_timeData[3] $crt_timeData[2]:$crt_timeData[1]:$crt_timeData[0]: $count_updated updates.\n";
