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
use Net::FTP;
use File::Path qw(make_path remove_tree);
use Data::Dumper;
$Data::Dumper::Sortkeys = 1;
use File::Listing qw(parse_dir);
use File::Find;
use File::Copy;
use XML::Simple;
use Encode;
use URI::Escape;
use Data::Compare;
use Mind_work::WikiCommons;

die "We need the temp path, the destination path and sc type:b1-5, f, i, h, r, d, t, k, z, a, p, cancel.\n" if ( $#ARGV != 2 );
our ($tmp_path, $to_path, $sc_type) = @ARGV;

die "sc type should be:b1-5, f, i, h, r, d, t, k, z, a, p, cancel.\n" if $sc_type !~ m/(^[fihrdtkzap]$)|(^b[1-5]$)|(^cancel$)/i;
$sc_type = uc $sc_type;

remove_tree("$tmp_path");
WikiCommons::makedir ("$tmp_path", 1);
WikiCommons::makedir ("$to_path", 1);
$tmp_path = abs_path("$tmp_path");
$to_path = abs_path("$to_path");
my $path_prefix = (fileparse(abs_path($0), qr/\.[^.]*/))[1]."";
WikiCommons::set_real_path($path_prefix);

my $sc_table = "mind_sc_ids_versions";
our $svn_pass = 'svncheckout';
our $svn_user = 'svncheckout';
our $files_info = "files_info.txt";
our $general_template_file = "$path_prefix/SC_template.txt";
my $svn_type = "remote";
# my $svn_type = "local";
# my $svn_local_path = "/mnt/SC/";
my $svn_update = "yes";
my $force_db_update = "no";
my $bulk_svn_update = "no";
my $update_only_wiki_db = "no";

my $ppt_local_files_prefix="/mnt/wiki_files/wiki_files/ppt_as_flash/";
my $ppt_apache_files_prefix="10.0.0.99/presentations/";

die "Template file missing.\n" if ! -e $general_template_file;

our $time = time();
my $svn_info_all = {};
my $url_sep = WikiCommons::get_urlsep;

our ($dbh, $dbh_mysql);

our @doc_types = (
'Market document', 'Market review document',
'Definition document', 'Definition review document',
'HLD document', 'HLD review docuemnt',
'Feature review document',
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
	unlink "$name" || die "Could not delete rtf file: $name.\n";
	return;
    }
    write_file("$name", $data);
}

sub write_file {
    my ($name, $txt) = @_;
    WikiCommons::write_file("$name", Encode::encode('utf8', $txt) );
}

sub general_info {
    my ($info, $index, $modules, $tester, $initiator, $dealer) = @_;
    local( $/, *FH ) ;
    open(FH, "$general_template_file") or die "Can't open file for read: $!.\n";
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
		    die "Strange crmid: $bug with $q == $w.\n" if ! defined $w || $w eq "";
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
# print "@$info[$index->{'customer_bug'}]   @$info[$index->{'crmid'}]\n";
	$general =~ s/%customer_bug%//;
    }
    $general =~ s/%type%/@$info[$index->{'changetype'}]/;
    push @categories, "ChangeType ".@$info[$index->{'changetype'}];
    $general =~ s/%category%/@$info[$index->{'category'}]/;
    $general =~ s/%project%/@$info[$index->{'projectname'}]/;
    $general =~ s/%product%/@$info[$index->{'productname'}]/;
    $general =~ s/%full_status%/@$info[$index->{'fullstatus'}]/;
    $general =~ s/%status%/@$info[$index->{'status'}]/;
    if (@$info[$index->{'cancel_remark'}] !~ m/^\s*$/) {
      $tmp = @$info[$index->{'cancel_remark'}];
      $tmp =~ s/\b([a-z][0-9]{4,})/[[SC:$1|$1]]/gi;
      $general =~ s/%cancel_reason%/Cancel remark: $tmp/;
    } else {
      $general =~ s/%cancel_reason%\n//;
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

    if (@$info[$index->{'fixesdescription'}] ne '' && @$info[$index->{'fixesdescription'}] ne ' ') {
	$tmp = @$info[$index->{'fixesdescription'}];
	$tmp =~ s/\r?\n/ <br\/>\n/g;
	$tmp =~ s/^(\*|\#|\;|\:|\=|\!|\||----|\{\|)/<nowiki>$1<\/nowiki>/gm;
	$tmp =~ s/\b([a-z][0-9]{4,})/[[SC:$1|$1]]/gmi;
	$general =~ s/%fix_description%/\'\'\'Fix descrption\'\'\':\n\n$tmp/;
    } else {
	$general =~ s/%fix_description%//;
    }
    $general =~ s/\n{3,}/\n\n\n/gm;

    return ($general, \@categories);
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
    my @info = ();
    my $sth = $dbh->prepare($SEL_INFO);
    $sth->execute();
    my $nr=0;
    while ( my @row=$sth->fetchrow_array() ) {
	die "too many rows\n" if $nr++;
	@info = @row;
	chomp @info;
    }
    return \%index, \@info;
}

sub sql_generate_select_changeinfo {
    my $hash_fields = {
	'fixesdescription'	=> 'nvl(fd.fixesdescription,\' \')',
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
	'customer'		=> 'nvl(a.customer,\' \')',
	'crmid'			=> 'nvl(a.requestref,\' \')',
	'category'		=> 'g.description',
	'fixversion'		=> 'nvl(a.fixversion,\' \')',
	'parent_change_id'	=> 'nvl(a.parent_change_id,\' \')',
	'relatedtasks'		=> 'nvl(a.relatedtasks,\' \')',
	'Market_SC'		=> 'nvl(mi.marketinfo,\' \')',
	'Description_SC'	=> 'nvl(f.function,\' \')',
	'HLD_SC'		=> 'nvl(hm.hld_memo,\' \')',
	'Messages_SC'		=> 'nvl(m.messages,\' \')',
	'Architecture_SC'	=> 'nvl(am.architecture_memo,\' \')',
	'initiator'		=> 'a.initiator',
	'tester'		=> 'nvl(a.testincharge,-1)',
	'dealer'		=> 'nvl(a.dealer,-1)',
	'cancel_remark'		=> 'nvl(a.cancelinformremark,\' \')',
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

# 	'Market_SC'		=> 'nvl(b1.marketinfo,\' \')',
# 	'Description_SC'	=> 'nvl(b2.function,\' \')',
# 	'HLD_SC'		=> 'nvl(b3.hld_memo,\' \')',
# 	'Messages_SC'		=> 'nvl(b4.messages,\' \')',
# 	'Architecture_SC'	=> 'nvl(b5.architecture_memo,\' \')',
# sc_marketinfo b1,
# sc_function b2,
# sc_hld_memo b3,
# sc_messages b4,
# sc_architecture_memo b5,
# and a.changeid = b1.changeid
# and a.changeid = b2.changeid
# and a.changeid = b3.changeid
# and a.changeid = b4.changeid
# and a.changeid = b5.changeid
    my $SEL_INFO = "
    select $select
    from SCCHANGE           a,
       SCPRODS              c,
       SCPROJECTS           p,
       SC_CATEGORIES        g,
       SC_MODULES_LIST      ml,
       SC_FIXES_DESCRIPTION fd,
       SC_MESSAGES          m,
       SC_MARKETINFO        mi,
       SC_HLD_MEMO          hm,
       SC_FUNCTION          f,
       SC_ARCHITECTURE_MEMO am
    where a.changeid = :CHANGEID
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
	die "too many rows\n" if $nr++;
	chomp @row;
	@info = @row;
    }

    return \@info;
}

sub sql_get_workers_names {
    my @ids = shift;
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
    print "-Get all db changes ". (time() - $time) .".\n";
    my $cond = "";
    my $ver = "";
    if ($sc_type eq 'B1') {
	$ver = "version >= \'5.0\' and version < \'5.3\'";
    } elsif ($sc_type eq 'B2') {
	$ver = "version >= \'5.3\' and version < \'6.0\'";
    } elsif ($sc_type eq 'B3') {
	$ver = "version >= \'6.0\' and version < \'6.5\'";
    } elsif ($sc_type eq 'B4') {
	$ver = "version >= \'6.5\' and version < \'7.0\'";
    } elsif ($sc_type eq 'B5') {
	$ver = "(version >= \'7.0\' or
	(nvl(version, 1) < \'5.0\' and nvl(fixversion, 6) > \'5.0\'))";
    }

    my $no_cancel = "and status <> 'Cancel'
	and status <> 'Inform-Cancel'
	and status <> 'Market-Cancel'";

    if ($sc_type =~ m/B[0-5]/) {
	$cond = "projectcode = 'B' and $ver";
    } elsif ($sc_type eq 'F') {
	$cond = "projectcode = 'F'";
    } elsif ($sc_type eq 'I') {
	$cond  = "projectcode = 'I' and (nvl(version,5) >= '4.00' or nvl(fixversion,5) >= '4.00')";
    } elsif ($sc_type eq 'H') {
	$cond  = "projectcode = 'H' and writtendatetime > '1Jan2008'";
    } elsif ($sc_type eq 'R') {
	$cond  = "projectcode = 'R'";
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
	$no_cancel = "((projectcode = 'B' and (version >= '5.0' or (nvl(version, 1) < '5.0' and nvl(fixversion,6) > '5.0'))) or
       (projectcode = 'F') or
       (projectcode = 'I' and (nvl(version, 5) >= '4.00' or nvl(fixversion,5) >= '4.00')) or
       (projectcode = 'H' and writtendatetime > '1Jan2008') or
       (projectcode = 'R') or
       (projectcode = 'T') or
       (projectcode = 'D' and (nvl(version, 3) >= '2.30' or nvl(fixversion, 3) >= '2.30')))
   and (status = 'Cancel' or status = 'Inform-Cancel' or
       status = 'Market-Cancel')";
    } else {
	die "Impossible.\n";
    }

    my $SEL_CHANGES = "select changeid, nvl(crc,0), status, projectcode
	from scchange
	where $cond $no_cancel";

    my $sth = $dbh->prepare($SEL_CHANGES);
    $sth->execute();
    my $crt_hash = {};
    while ( my @row=$sth->fetchrow_array() ) {
	$crt_hash->{$row[0]} = \@row;
    }
    print "+Get all db changes ". (time() - $time) .".\n";
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
	die "too many rows\n" if $#row>1;
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

sub sql_get_relpath {
    my $SEL = "select svn.parametervalue
  from (select parametervalue
          from scparameters
         where section = \'SVN\'
           and parameterkey = \'SVN_DOC_REPOS\') svn";
    my $sth = $dbh->prepare($SEL);
    $sth->execute();
    while ( my @row=$sth->fetchrow_array() ) {
	die "too many rows\n" if $#row>1;
	return $row[0];
    }
}

sub get_previous {
    my $path = shift;
    my @info = ();
    open(FH, "$path") or die "Can't open file $path.\n";
    @info = <FH>;
    close(FH);
    chomp @info;
    my $info_hash = {};
    foreach my $line (@info) {
	my @all = split(/;/, $line);
	return if (@all < 1);
	$all[0] =~ s/^[0-9]{1,} //;
# 	next if $all[0] eq "Categories";
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
#     print "\t*** Connecting again: $nr_retries.\n" if $nr_retries>=0;
#     $ftp = Net::FTP->new("$ip", Debug => 0, Timeout => 300) or die "Cannot connect to some.host.name: $@";
#     $ftp->login("$user","$pass") or die "Cannot login ", $ftp->message;
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
# 	    die "Unknown file type : $type for $name at $change_id in $remote_path.\n";
# 	}
#     }
#     foreach my $file (@files) {
# 	print "\tGet file $file.\n";
# 	my $res = $ftp->get("$file", "$local_dir/$file");
# 	my $err = $!;
# 	if (!defined $res && $ftp->message =~ m/: The system cannot find the file specified.\s*$/) {
# 	    print "\t=== Fucking weird file name: $file\n";
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
#     print "Connect to ftp.\n";
#     our $nr_retries = -1;
#     our $ftp;
#
#
#     ftpconnect;
#     foreach my $change_id (sort @ids){
# 	my $dif = time() - $time;
# 	print " ftp for $change_id ".$count++ ." from ". scalar @ids."\t$dif.\n";
# 	foreach my $type ($ftp_uri_def, $ftp_uri_mrkt, $ftp_uri_test) {
# 	    print "   ftp for dir $type/$change_id\t$dif.\n";
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
# 		    print "\t=== Error with message: $status.\n";
# 		    ftpconnect;
# 		}
# 	    }
# 	}
# 	finddepth sub { rmdir ($File::Find::name) if -d ;}, "$ftp_tmp_path/$change_id";
# 	move("$ftp_tmp_path/$change_id", "$result_dir/$change_id");
#     }
#     $ftp->quit;
#     print "Disconnect to ftp.\n";
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
    print "\t-SVN list for $file.\t". (time() - $time)."\n" if defined $file;
    my $res = "";;
    if (exists $svn_info_all->{$dir}) {
	$res = $svn_info_all->{$dir}->{$file};
    } else {
	$dir .= "/$file" if defined $file;
	my $xml = `svn list --xml --non-interactive --no-auth-cache --trust-server-cert --password $svn_pass --username $svn_user \'$dir\' 2> /dev/null`;
	if ($?) {
	    print "\tError $? for svn.\n";
	    return undef;
	}
	my $hash = XMLin($xml);
	$res = $hash->{'list'}->{'entry'} if exists $hash->{'list'}->{'entry'};
    }
    print "\t+SVN list for $file.\t". (time() - $time)."\n" if defined $file;
    return $res;
}

sub write_control_file {
    my ($hash, $dir, $categories) = @_;
    my $text = "";
    print "\tWrite control file\n";
    for (my $i=0;$i<@doc_types;$i++) {
	next if ! exists $hash->{$doc_types[$i]};
	my $name = $hash->{$doc_types[$i]}->{'name'} || '';
	my $size = '';
	$size = $hash->{$doc_types[$i]}->{'size'} if ( defined $hash->{$doc_types[$i]}->{'size'} );
	my $rev = $hash->{$doc_types[$i]}->{'revision'} || '';
	my $date = $hash->{$doc_types[$i]}->{'date'} || '';
	$text .= (1000 + $i) ." $doc_types[$i];$name;$size;$rev;$date\n";
    }

    $text .= "SC_info;$hash->{'SC_info'}->{'name'};$hash->{'SC_info'}->{'size'};$hash->{'SC_info'}->{'revision'};$hash->{'SC_info'}->{'date'}\n";
    $text .= "Categories;". (join ';',@$categories). "\n" if defined $categories && scalar @$categories;
    write_file("$dir/$files_info", "$text");
}

sub search_for_presentations {
    my ($ftp_ip, $ftp_def, $ftp_market, $ftp_test, $change_id) = @_;
    my $local_path = "$ppt_local_files_prefix/$ftp_ip";
    my $apache_path = "$ppt_apache_files_prefix/$ftp_ip";
    my $i = 0;
    my $control = "";
    my $text = ();
    foreach my $ftp_dir ($ftp_def, $ftp_market, $ftp_test) {
      my $q = "$local_path/$ftp_dir/$change_id/";
      my $w = "$apache_path/$ftp_dir/$change_id/";
      foreach my $file (sort <$q/*>){
	$i++;
	next if $file !~m/\.swf$/i;
	my ($name, $dir, $suffix) = fileparse($file, qr/\.[^.]*/);
	my $apache_file = "$w$name$suffix";
	$apache_file =~ s/\/+/\//g;
	$apache_file = uri_escape( $apache_file,"^A-Za-z\/:0-9\-\._~%" );
	my $ftp_file = "$ftp_ip/$ftp_dir/$change_id/$name.ppt";
	$ftp_file = uri_escape( $ftp_file,"^A-Za-z\/:0-9\-\._~%" );
	$text .= "
\n<toggledisplay status=\"hide\" showtext=\"$name\" hidetext=\"Close presentation\">
To open the presentation in a new tab, click [http://$apache_file here]. The original document can be found [ftp://$ftp_file here].
<swf width=\"800\" height=\"500\" >http://$apache_file</swf>
</toggledisplay>\n";
	$control .= "$name";
      }
    }
#     $control .= "v1.5" if $control ne "";
    return ($text, $control);
}

sub clean_existing_dir {
    my ($change_id, $svn_docs) = @_;
    return if ! -e "$to_path/$change_id";
    opendir(DIR, "$to_path/$change_id") || die "Cannot open directory $to_path/$change_id: $!.\n";
    my @files = grep { (!/^\.\.?$/) && -f "$to_path/$change_id/$_" && "$_" =~ /\.doc$/} readdir(DIR);
    closedir(DIR);
    foreach my $file (@files){
	my ($name,$dir,$suffix) = fileparse($file, qr/\.[^.]*/);
	if ( ! exists $svn_docs->{$name}) {
	    print "\tDelete file $file because it doesn't exist on svn anymore.\n";
	    unlink("$to_path/$change_id/$file") or die "Could not delete the file $file: $!\n" ;
	}
    }
}

sub remove_old_dirs {
    my @scdirs = @_;
    ## remove not needed directories
    opendir(DIR, "$to_path") || die "Cannot open directory $to_path: $!.\n";
    my @dirs = grep { (!/^\.\.?$/) && -d "$to_path/$_"} readdir(DIR);
    closedir(DIR);
    my ($only_in_sc, $only_in_dirs, $common) = WikiCommons::array_diff( \@scdirs, \@dirs);
    foreach my $dir (@$only_in_dirs) {
	print "Remove old dir $dir.\n";
	remove_tree("$to_path/$dir");
    }
}

sub add_versions_to_wiki_db {
    my ($change_id, $info, $index) = @_;
    my $sth_mysql = $dbh_mysql->prepare("REPLACE INTO $sc_table VALUES ('$change_id', '@$info[$index->{'fixversion'}]', '@$info[$index->{'buildversion'}]', ' @$info[$index->{'version'}]', '@$info[$index->{'prodversion'}]')");

#     $sth_mysql->bind_param( ":SC_ID", $change_id );
#     $sth_mysql->bind_param( ":FIXVERSION", @$info[$index->{'fixversion'}] );
#     $sth_mysql->bind_param( ":BUILDVERSION", @$info[$index->{'buildversion'}] );
#     $sth_mysql->bind_param( ":VERSION", @$info[$index->{'version'}] );
#     $sth_mysql->bind_param( ":PRODVERSION", @$info[$index->{'prodversion'}] );

    $sth_mysql->execute();
    $sth_mysql->finish();
}

# 10.0.0.232 service25, service25

# $ftp_uri = "ftp:\\\\@$info_comm[$index_comm->{'FTP_USER'}]:@$info_comm[$index_comm->{'FTP_PASS'}]\@@$info_comm[$index_comm->{'FTP_IP'}]";


### connect to mysql to use the wikidb
my ($wikidb_server, $wikidb_name, $wikidb_user, $wikidb_pass) = ();
open(FH, "/var/www/html/wiki/LocalSettings.php") or die "Can't open file for read: $!.\n";
while (<FH>) {
  $wikidb_server = $2 if $_ =~ m/^(\s*\$wgDBserver\s*=\s*\")(.+)(\"\s*;\s*)$/;
  $wikidb_name = $2 if $_ =~ m/^(\s*\$wgDBname\s*=\s*\")(.+)(\"\s*;\s*)$/;
  $wikidb_user = $2 if $_ =~ m/^(\s*\$wgDBuser\s*=\s*\")(.+)(\"\s*;\s*)$/;
  $wikidb_pass = $2 if $_ =~ m/^(\s*\$wgDBpassword\s*=\s*\")(.+)(\"\s*;\s*)$/;
}
close(FH);
# my $dsn_mysql = ;
$dbh_mysql = DBI->connect("DBI:mysql:database=$wikidb_name;host=$wikidb_server", "$wikidb_user", "$wikidb_pass");
print "$sc_table";
my $sth_mysql = $dbh_mysql->prepare("CREATE TABLE IF NOT EXISTS $sc_table (
SC_ID VARCHAR( 255 ) NOT NULL ,
FIXVERSION VARCHAR( 255 ) ,
BUILDVERSION VARCHAR( 255 ) ,
VERSION VARCHAR( 255 ) ,
PRODVERSION VARCHAR( 255 ) ,
PRIMARY KEY ( SC_ID ))");
$sth_mysql->execute();
$sth_mysql->finish();

### connect to oracle
$ENV{NLS_LANG} = 'AMERICAN_AMERICA.AL32UTF8';
sql_connect('10.0.0.103', 'SCROM', 'scview', 'scview');
my $db_relpath = sql_get_relpath();
my ($index_comm, $info_comm) = sql_get_common_info();
write_common_info ($index_comm, $info_comm);
my $crt_hash = sql_get_all_changes();
my ($index, $SEL_INFO) = sql_generate_select_changeinfo();

my $total = scalar (keys %$crt_hash);
# print "total $total\n"; exit 1;
remove_old_dirs(keys %$crt_hash);

if ($bulk_svn_update eq "yes"){
    foreach my $key (sort keys %$index_comm) {
	my $retries = 0;
	my $tmp = @$info_comm[$index_comm->{$key}];
	next if ($tmp !~ "^http://" || defined $svn_info_all->{$tmp});
	while ( ! defined $svn_info_all->{$tmp} && $retries < 3){
	    print "\tRetrieve svn list for $key.\t". (time() - $time) ."\n";
	    my $res = svn_list($tmp);
	    $svn_info_all->{$tmp} = $res if defined $res;
	    $retries++;
	}
	die if $retries == 3;
    };
}

## problem: after the first run we can have missing documents, but the general_info will not be updated
my $count = 0;
foreach my $change_id (sort keys %$crt_hash){
# next if $change_id ne "B87308";
## special chars: B06390
## docs B71488
    $count++;
    my $dif = time() - $time;
    my $work_dir = "$tmp_path/$change_id";
    WikiCommons::makedir("$work_dir");
    my $todo = {};
    my $missing_documents = {};
    my $crt_info = {};
    print "*************\n-Start working for $change_id: nr $count of $total.\t$dif\n";
    my $prev_info = get_previous("$to_path/$change_id/$files_info") if (-e "$to_path/$change_id/$files_info");

    ### svn updates (first svn, because we need missing documents)
    my $update_control_file = 0;
    if ($svn_update ne "no" && $update_only_wiki_db ne "yes") {
	my $svn_docs = sql_get_svn_docs($change_id);
	clean_existing_dir($change_id, $svn_docs);

	foreach my $key (sort keys %$svn_docs) {
	    my $dir = @$info_comm[$index_comm->{$key}];
# 	    $dir =~ s/$db_relpath/$svn_local_path/ if ($svn_type eq "local");
	    my $file = $svn_docs->{$key};
	    my $res = svn_list("$dir", "$file");

	    my $doc_rev = $res->{'commit'}->{'revision'};
	    my $doc_size = $res->{'size'};
	    if ( ! defined $res || (! defined $doc_rev && ! defined $doc_size)) {
		print "\tSC $change_id says we have document for $key, but we don't have anything on svn.\n";
		$missing_documents->{$key} = "$dir/$file";
		next;
	    }
	    delete $prev_info->{$key} if (!(-e "$to_path/$change_id/$key.doc" && -s "$to_path/$change_id/$key.doc" == $doc_size));
	    $crt_info->{$key}->{'name'} = $svn_docs->{$key};
	    $crt_info->{$key}->{'size'} = $doc_size;
	    $crt_info->{$key}->{'revision'} = $doc_rev;

	    if ( ! Compare($crt_info->{$key}, $prev_info->{$key}) ) {
		print "\tUpdate svn http for $key.\n";
		my $file_res = WikiCommons::http_get("$dir/$file", "$work_dir", "$svn_user", "$svn_pass");
		move("$file_res", "$work_dir/$key.doc") || die "can't move file $file_res to $work_dir/$key.doc: $!.\n";
		## like this in order to not update everything after we added the date to docs
		$crt_info->{$key}->{'date'} =  $res->{'commit'}->{'date'};
		$update_control_file++;
	    }
	}
    }

    my ($presentations, $control) = search_for_presentations(@$info_comm[$index_comm->{'FTP_IP'}], @$info_comm[$index_comm->{'FTP_def_attach'}], @$info_comm[$index_comm->{'FTP_market_attach'}], @$info_comm[$index_comm->{'FTP_test_attach'}], $change_id);
    ## db update
    my $arr = $crt_hash->{$change_id};

    $crt_info->{'SC_info'}->{'name'} = @$arr[0];
    $crt_info->{'SC_info'}->{'size'} = @$arr[1].$control;
    $crt_info->{'SC_info'}->{'revision'} = @$arr[2];
    my $cat = ();
    ## like this in order to not update everything after we added the date to docs
    $crt_info->{'SC_info'}->{'date'} = "sc_date is not used";
    if ( ! Compare($crt_info->{'SC_info'}, $prev_info->{'SC_info'}) || $update_control_file || $force_db_update eq "yes" || $update_only_wiki_db eq "yes") {
 	print "\tUpdate SC info.\n";

	my $prev = 'NULL';
	$prev = $prev_info->{'SC_info'}->{'size'} if defined $prev_info->{'SC_info'}->{'size'};
	print "\tChanged CRC: $crt_info->{'SC_info'}->{'size'} from $prev.\n" if ( defined $crt_info->{'SC_info'}->{'size'} && "$crt_info->{'SC_info'}->{'size'}" ne "$prev");

	$prev = 'NULL';
	$prev = $prev_info->{'SC_info'}->{'revision'} if defined $prev_info->{'SC_info'}->{'revision'};
	print "\tChanged status: $crt_info->{'SC_info'}->{'revision'} from $prev.\n" if ( defined $crt_info->{'SC_info'}->{'revision'} && "$crt_info->{'SC_info'}->{'revision'}" ne "$prev");

	my $info_ret = sql_get_changeinfo($change_id, $SEL_INFO);
	## some SR's are completly empty, so ignore them
	next if (scalar @$info_ret == 0);
	add_versions_to_wiki_db($change_id, $info_ret, $index);
	next if $update_only_wiki_db eq "yes";
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
	write_file ("$work_dir/General_info.wiki" ,$txt);
	write_rtf ("$work_dir/1 Market_SC.rtf", @$info_ret[$index->{'Market_SC'}]);
	write_rtf ("$work_dir/2 Description_SC.rtf", @$info_ret[$index->{'Description_SC'}]);
	write_rtf ("$work_dir/3 HLD_SC.rtf", @$info_ret[$index->{'HLD_SC'}]);
	write_rtf ("$work_dir/4 Messages_SC.rtf", @$info_ret[$index->{'Messages_SC'}]);
	write_rtf ("$work_dir/5 Architecture_SC.rtf", @$info_ret[$index->{'Architecture_SC'}]);
	$update_control_file++;
    }

    write_control_file($crt_info, $work_dir, $cat) if $update_control_file;

    WikiCommons::move_dir("$work_dir", "$to_path/$change_id/");
    print "+Finish working for $change_id: nr $count of $total.\t$dif\n";
}

$dbh->disconnect if defined($dbh);
$dbh_mysql->disconnect() if defined($dbh_mysql);

print "Done.\n";
