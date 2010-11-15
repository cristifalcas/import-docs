#!/usr/bin/perl -w
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

## ~ 10 hours first run
use lib "./our_perl_lib/lib";
use DBI;
use Net::FTP;
use LWP::UserAgent;
use File::Path qw(make_path remove_tree);
use Data::Dumper;
use File::Basename;
use File::Listing qw(parse_dir);
use File::Find;
use File::Copy;
use Cwd 'abs_path','chdir';
use XML::Simple;
# use File::Find::Rule;
use Data::Compare;
use Mind_work::WikiCommons;

die "We need the temp path and the destination path.\n" if ( $#ARGV != 1 );
our ($tmp_path, $to_path) = @ARGV;

remove_tree("$tmp_path");
WikiCommons::makedir ("$tmp_path");
WikiCommons::makedir ("$to_path");
$tmp_path = abs_path("$tmp_path");
$to_path = abs_path("$to_path");

our $svn_pass = 'svncheckout';
our $svn_user = 'svncheckout';
our $files_info = "files_info.txt";
our $general_template_file = "./SC_template.txt";
my $bulk_svn_update = "no";
my $svn_update = "yes";
my $force_sc_update = "no";
our $time = time();
my $url_sep = WikiCommons::get_urlsep;
my $path_prefix = (fileparse(abs_path($0), qr/\.[^.]*/))[1]."";
WikiCommons::set_real_path($path_prefix);

our $dbh;
our $request;

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

if ($force_sc_update eq "yes"){
    $bulk_svn_update = "no";
}

# sub makedir {
#     my $dir = shift;
#     make_path ("$dir", {owner=>'wiki', group=>'nobody', error => \my $err});
#     if (@$err) {
# 	for my $diag (@$err) {
# 	    my ($file, $message) = %$diag;
# 	    if ($file eq '') { die "general error: $message.\n"; }
# 	    else { die "problem unlinking $file: $message.\n"; }
# 	}
# 	die "Can't make dir $dir.\n";
#     }
# }

sub write_rtf {
    my ($name, $data) = @_;
    $data =~ s/(^\s+)|(\s+$)//;
    $data =~ s/\$\$\@\@/\'/gs;
    return if (! defined $data || $data eq "");
    open (FILE_RTF, ">$name") or die "can't open file $name for writing: $!\n";
    print FILE_RTF "$data";
    close (FILE_RTF);
}

sub write_file {
    my $path = shift;
    my $text = shift;
    open (FILE, ">$path") or die "can't open file $path for writing: $!\n";
    print FILE "$text";
    close (FILE);
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
    $tmp = "";
    foreach (@$tester) {
	s/\ /_/g;
	$tmp .= "[mailto:$_\@mindcti.com $_]\n";
    }
    $general =~ s/%tester%/$tmp/g;
    $tmp = @$info[$index->{'customer'}];
    my @all_custs = split ',', @$info[$index->{'customer'}];

    foreach my $cust (@all_custs) {
	next if $cust =~ m/^\s*$/;
	$cust =~ s/(^\s*)|(\s*$)//;
	my $q = WikiCommons::get_correct_customer($cust);
	push @categories, "customer $cust";
	$cust = "\[\[:Category:$cust\|$cust\]\]";
    }

    if (scalar @all_custs){
	$tmp = join ' ', @all_custs;
	$general =~ s/%customer%/\'\'\'Customer\'\'\': $tmp/;
    } else {
	$general =~ s/%customer%//;
    }

    if (@$info[$index->{'customer_bug'}] eq 'Y' && @$info[$index->{'crmid'}] !~ m/^\s*$/) {
	$tmp = @$info[$index->{'crmid'}];
	$tmp =~ s/(^\s+)|(\s+$)//g;
	$tmp =~ s/\s+/ /g;
	if ($tmp =~ m/^\s*(.*)?(\s*\/\s*|\s+)([0-9]{1,})\s*$/){
	    my $q = $1;
	    my $w = $2;
	    $q = WikiCommons::get_correct_customer( $q );
	    $tmp = "CRM:$q -- $w";
	} else {
	    die "Strange customer bug string: $tmp.\n" ;
	}
	$general =~ s/%customer_bug%/\'\'\'Customer bug\'\'\' (CRM ID): [[$tmp]]/;
    } else {
	$general =~ s/%customer_bug%//;
    }
    $general =~ s/%type%/@$info[$index->{'changetype'}]/;
    $general =~ s/%category%/@$info[$index->{'category'}]/;
    $general =~ s/%project%/@$info[$index->{'projectname'}]/;
    $general =~ s/%product%/@$info[$index->{'productname'}]/;
    $general =~ s/%full_status%/@$info[$index->{'fullstatus'}]/;
    $general =~ s/%status%/@$info[$index->{'status'}]/;
    $tmp = @$info[$index->{'fixversion'}];
    $tmp =~ s/(^\s*)|(\s*$)//;
    if ($tmp && $tmp ne ''){
	my ($main, $ver, $ver_fixed, $big_ver, $ver_sp, $ver_without_sp) = WikiCommons::check_vers($tmp, $tmp);
	$general =~ s/%fix_version%/[[:Category:$ver_fixed|$ver_fixed]]/g;
    }

    push @categories, "version ". @$info[$index->{'version'}];

    $general =~ s/%version%/@$info[$index->{'version'}]/;
    $general =~ s/%build_version%/@$info[$index->{'buildversion'}]/;
    $general =~ s/%prod_version%/@$info[$index->{'prodversion'}]/;
    $general =~ s/%parent_id%/SC:@$info[$index->{'parent_change_id'}]\|@$info[$index->{'parent_change_id'}]/;
    my $related_tasks = "";
    my @related = split ',', @$info[$index->{'relatedtasks'}];
    for (my $i=0;$i<@related;$i++){
	next if ($related[$i] eq @$info[$index->{'changeid'}] || $related[$i] eq '' || $related[$i] eq ' ');
	if ($i%6 != 0){
	    $related_tasks .= "| '''[[SC:$related[$i]|$related[$i]]]'''\n";
	} else {
	    $related_tasks .= "|-\n| '''[[SC:$related[$i]|$related[$i]]]'''\n";
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
	$general =~ s/%fix_description%/\'\'\'Fix descrption\'\'\':\n\n$tmp/;
    } else {
	$general =~ s/%fix_description%//;
    }
#     $general .= "\n\n";
#     foreach my $cat (@categories) {
# 	$general .= "[[Category:$cat]]\n";
#     }

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
    $SEL_INFO = "select $select" . $SEL_INFO . " where prj.projectcode = 'B'";

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
	'fixesdescription'	=> 'nvl(a.fixesdescription,\' \')',
	'changeid'		=> 'a.changeid',
	'modules'		=> 'nvl(a.modules,\' \')',
	'moduleslist'		=> 'nvl(a.moduleslist,\' \')',
	'buildversion'		=> 'nvl(a.buildversion,\' \')',
	'prodversion'		=> 'nvl(a.prodversion,\' \')',
	'version'		=> 'nvl(a.version,\' \')',
	'status' 		=> 'nvl(a.status,\' \')',
	'fullstatus'		=> 'nvl(a.fullstatus,\' \')',
	'projectname'		=> 'f.projectname',
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
	'Market_SC'		=> 'nvl(a.marketinfo,\' \')',
	'Description_SC'	=> 'nvl(a.function,\' \')',
	'Architecture_SC'	=> 'nvl(a.architecture_memo,\' \')',
	'HLD_SC'		=> 'nvl(a.hld_memo,\' \')',
	'Messages_SC'		=> 'nvl(a.messages,\' \')',
	'initiator'		=> 'a.initiator',
	'tester'		=> 'nvl(a.testincharge,-1)',
	'dealer'		=> 'nvl(a.dealer,-1)',
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
    from scchange a,
	scprods c,
	scprojects f,
	sc_categories g
    where a.changeid = :CHANGEID
    and a.projectcode = c.projectcode
    and c.productid = a.product
    and f.projectcode = a.projectcode
    and g.id = a.category_id";

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
	@info = @row;
	chomp @info;
    }
    die "nica in $change_id\n" if (scalar @info == 0);

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
    my $SEL_CHANGES = "select changeid, nvl(crc,0), status
	from scchange
	where projectcode = \'B\'
	and version >= \'5.0\'
	and status <> \'Cancel\'
	and status<> \'Inform-Cancel\'
	and status <> \'Market-Cancel\'
	";

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

sub http_svn_get {
    my ($url_path, $local_path) = @_;
    my $ua = LWP::UserAgent->new;
    my $count = 1;

    print "\t-Get from svn url $url_path.\n";
    my ($name,$dir,$suffix) = fileparse($url_path, qr/\.[^.]*/);
    my $retries = 0;
    while ($retries < 3) {
	$request->uri( $url_path );
	my $response = $ua->request($request, "$local_path/$name$suffix");
	if ($response->is_success) {
	    print $response->decoded_content;
	    last;
	}else {
	    if ($response->status_line eq "404 Not Found") {
		return;
	    } else {
		print Dumper($response->status_line) ."\tfor file $url_path\n" ;
		$retries++;
	    }
	}
    }
    print "\t+Get from svn url $url_path.\n";
    return "$local_path/$name$suffix";
}

sub write_common_info {
    my ($index_comm, $info_comm) = @_;
    my $text = "";
    foreach my $key (sort keys %$index_comm) {
	$text .= "$key = @$info_comm[$index_comm->{$key}]\n";
    }
    write_file("$to_path/common_info", $text);
}

sub svn_info {
    my $path = shift;
    print "\t-SVN info for $path.\t". (time() - $time)."\n";
    my $xml = `svn list --xml --non-interactive --no-auth-cache --trust-server-cert --password $svn_pass --username $svn_user \'$path\' 2> /dev/null`;
    if ($?) {
	print "\tError $? for svn.\n";
	return;
    }
    my $hash = XMLin($xml);
    print "\t+SVN info for $path.\t". (time() - $time)."\n";
    return $hash;
}

sub write_control_file {
    my ($hash, $dir, $categories) = @_;
    my $text = "";
    print "Write control file\n";
    for (my $i=0;$i<@doc_types;$i++) {
	next if ! exists $hash->{$doc_types[$i]};
	my $name = $hash->{$doc_types[$i]}->{'name'} || '';
	my $size = '';
	$size = $hash->{$doc_types[$i]}->{'size'} if ( defined $hash->{$doc_types[$i]}->{'size'} );
	my $rev = $hash->{$doc_types[$i]}->{'revision'} || '';
	$text .= (1000 + $i) ." $doc_types[$i];$name;$size;$rev\n";
    }

    $text .= "SC_info;$hash->{'SC_info'}->{'name'};$hash->{'SC_info'}->{'size'};$hash->{'SC_info'}->{'revision'}\n";
    $text .= "Categories;". (join ';',@$categories). ";"x(3-(scalar @$categories))."\n" if scalar @$categories;
    write_file("$dir/$files_info", "$text");
}

sub move_dir {
    my ($src, $trg) = @_;
    die "\tTarget $trg is a file.\n" if (-f $trg);
    if (! -d $trg) {
	move("$src", "$trg") or die "Move dir $src to $trg failed: $!\n";
    } else {
	opendir(DIR, "$src") || die("Cannot open directory $src.\n");
	my @files = grep { (!/^\.\.?$/) } readdir(DIR);
	closedir(DIR);
	foreach my $file (@files){
	    move("$src/$file", "$trg/") or die "Move file $src/$file to $trg failed: $!\n";
	}
	remove_tree("$src");
    }
}
# 10.0.0.232 service25, service25
#     select * from tblscmainrecord t where rscmainreccustcode=477 and rscmainrecscno=124;
#     select * from tblscevents t where rsceventscompanycode=477 and rsceventsscno=124;
#     select * from tblsceventdoc t where rsceventdoccompanycode=477 and rsceventdocscno=124;
#     t.rsceventdoctype='B' - attachement
#     select * from tblcustomers t where rcustiddisplay='MSTelcom'
#select * from tblcustomercontacts t
#select * from tblcustomeraddresses t
# $ftp_uri = "ftp:\\\\@$info_comm[$index_comm->{'FTP_USER'}]:@$info_comm[$index_comm->{'FTP_PASS'}]\@@$info_comm[$index_comm->{'FTP_IP'}]";

$ENV{NLS_LANG} = 'AMERICAN_AMERICA.AL32UTF8';
sql_connect('10.0.0.103', 'SCROM', 'scview', 'scview');
my ($index_comm, $info_comm) = sql_get_common_info();
write_common_info ($index_comm, $info_comm);
my $crt_hash = sql_get_all_changes();
## remove not needed directories
opendir(DIR, "$to_path") || die "Cannot open directory $to_path: $!.\n";
my @dirs = grep { (!/^\.\.?$/) && -d "$to_path/$_"} readdir(DIR);
closedir(DIR);
my @scdirs = keys %$crt_hash;
my ($only_in_sc, $only_in_dirs, $common) = WikiCommons::array_diff( \@scdirs, \@dirs);
foreach my $dir (@$only_in_dirs) {
    print "Remove old dir $dir.\n";
    remove_tree("$to_path/$dir");
}

my $svn_info_all = {};
if ($bulk_svn_update eq "yes"){
    foreach my $key (sort keys %$index_comm) {
	my $retries = 0;
	my $tmp = @$info_comm[$index_comm->{$key}];
	# print "$key = @$info_comm[$index_comm->{$key}]\n";
	next if ($tmp !~ "^http://" || defined $svn_info_all->{$tmp});
	while ( ! defined $svn_info_all->{$tmp} && $retries < 3){
	    print "\tRetrieve svn info for $key.\t". (time() - $time) ."\n";
	    $svn_info_all->{$tmp} = svn_info($tmp);
	    $retries++;
	}
	die if $retries == 3;
    };
}

my ($index, $SEL_INFO) = sql_generate_select_changeinfo();
## (scalar @dirs) - (scalar @$only_in_dirs)
my $count = 0;
my $total = scalar (keys %$crt_hash);
foreach my $change_id (sort keys %$crt_hash){
#     next if $change_id ne "B02315";
# B099626, B03761
## special chars: B06390
## docs B71488
    $count++;
    my $work_dir = "$tmp_path/$change_id";
    my $dif = time() - $time;
    my $svn_docs = sql_get_svn_docs($change_id);
    my $prev_info = {};
    my $crt_info = {};
    print "*************\n-Start working for $change_id: nr $count of $total.\t$dif\n";

    # get all doc files from "$to_path/$change_id" and remove them if they are not in $svn_docs
    if (-e "$to_path/$change_id/$files_info"){
	$prev_info = get_previous("$to_path/$change_id/$files_info");
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

    my $missing_documents = {};
    my $arr = $crt_hash->{$change_id};
    $crt_info->{'SC_info'}->{'name'} = @$arr[0];
    $crt_info->{'SC_info'}->{'size'} = @$arr[1];
    $crt_info->{'SC_info'}->{'revision'} = @$arr[2];
    my $todo = {};
    $todo->{'SC_info'} = $change_id if ! Compare($crt_info->{'SC_info'}, $prev_info->{'SC_info'});
    next if Compare($crt_info->{'SC_info'}, $prev_info->{'SC_info'}) && $svn_update eq "no" && $force_sc_update ne "yes";
    foreach my $key (sort keys %$svn_docs) {
	if ($force_sc_update eq "yes" && defined $prev_info->{'SC_info'}) {
	    $crt_info = $prev_info;
	    last;
	}

	next if (! exists $svn_docs->{$key});
	my $res = {};
	if ($bulk_svn_update eq "yes") {
	    $res = $svn_info_all->{@$info_comm[$index_comm->{$key}]}->{'list'}->{'entry'}->{$svn_docs->{$key}};
	} else {
	    $res = svn_info("@$info_comm[$index_comm->{$key}]/$svn_docs->{$key}");
	    $res = $res->{'list'}->{'entry'};
	}
	my ($doc_rev, $doc_size);
	if (defined $res) {
	    $doc_rev = $res->{'commit'}->{'revision'};
	    $doc_size = $res->{'size'};
	}
	delete $prev_info->{$key} if (!(-e "$to_path/$change_id/$key.doc" && -s "$to_path/$change_id/$key.doc" == $doc_size));
	if (! defined $doc_rev && ! defined $doc_size) {
	    print "\tSC $change_id says we have document for $key, but we don't have anything on svn.\n";
	    my $svn_dir = @$info_comm[$index_comm->{$key}];
	    $missing_documents->{$key} = "$svn_dir/$svn_docs->{$key}";
	    next;
	}
	$crt_info->{$key}->{'name'} = $svn_docs->{$key};
	$crt_info->{$key}->{'size'} = $doc_size;
	$crt_info->{$key}->{'revision'} = $doc_rev;
	$todo->{$key} = "$svn_docs->{$key}" if (! Compare($crt_info->{$key}, $prev_info->{$key}) );
    }

    next if Compare($crt_info, $prev_info) && $force_sc_update ne "yes";
    WikiCommons::makedir("$work_dir");
    foreach my $key (keys %$svn_docs) {
	if ( exists $todo->{$key} ) {
	    print "\tUpdate svn http for $key.\n";
	    my $svn_dir = @$info_comm[$index_comm->{$key}];
	    $request = HTTP::Request->new(GET => "$svn_dir");
	    $request->authorization_basic("$svn_user", "$svn_pass");
	    my $file = http_svn_get("$svn_dir/$svn_docs->{$key}", "$work_dir");
	    if (! defined $file){
		$missing_documents->{$key} = "$svn_dir/$svn_docs->{$key}";
	    } else {
		move("$file", "$work_dir/$key.doc") || die "can't move file $file to $work_dir/$key.doc: $!.\n";
	    }
	}
    }

    my $cat = ();
    if (defined $todo->{'SC_info'} || $force_sc_update eq "yes") {
 	print "\tUpdate SC info.\n";
	my $prev = $prev_info->{'SC_info'}->{'size'} || 'NULL';

	print "\tChanged CRC: $crt_info->{'SC_info'}->{'size'} from $prev.\n" if ( defined $crt_info->{'SC_info'}->{'size'} && $crt_info->{'SC_info'}->{'size'} ne $prev);
	$prev = $prev_info->{'SC_info'}->{'revision'} || 'NULL';
	print "\tChanged status: $crt_info->{'SC_info'}->{'revision'} from $prev.\n" if ( defined $crt_info->{'SC_info'}->{'revision'} && $crt_info->{'SC_info'}->{'revision'} ne $prev);
	my $info_ret = sql_get_changeinfo($change_id, $SEL_INFO);
	my $modules = sql_get_modules( split ',', @$info_ret[$index->{'modules'}] ) if defined @$info_ret[$index->{'modules'}];
	my $tester = sql_get_workers_names( split ',', @$info_ret[$index->{'tester'}] ) if defined @$info_ret[$index->{'tester'}];
	my $initiator = sql_get_workers_names( split ',', @$info_ret[$index->{'initiator'}] );
	my $dealer = sql_get_dealer_names( split ',', @$info_ret[$index->{'dealer'}] );
	my ($txt, $categories) = general_info($info_ret, $index, $modules, $tester, $initiator, $dealer);
	$cat = $categories;
	foreach my $key (sort keys %$missing_documents) {
	    $txt .= "\nMissing \'\'\'$key\'\'\' from [$missing_documents->{$key} this] svn address, but database says it should exist.\n";
	}

	write_file ("$work_dir/General_info.wiki" ,$txt);
	write_rtf ("$work_dir/1 Market_SC.rtf", @$info_ret[$index->{'Market_SC'}]);
	write_rtf ("$work_dir/2 Description_SC.rtf", @$info_ret[$index->{'Description_SC'}]);
	write_rtf ("$work_dir/3 HLD.rtf", @$info_ret[$index->{'HLD_SC'}]);
	write_rtf ("$work_dir/4 Messages_SC.rtf", @$info_ret[$index->{'Messages_SC'}]);
	write_rtf ("$work_dir/5 Architecture_SC.rtf", @$info_ret[$index->{'Architecture_SC'}]);
    }

    $cat = [ $prev_info->{'Categories'}->{'name'} || "", $prev_info->{'Categories'}->{'size'} || "", $prev_info->{'Categories'}->{'revision'} || "" ] if ! defined $cat;

    write_control_file($crt_info, $work_dir, $cat);
    move_dir("$work_dir", "$to_path/$change_id/");
    print "+Finish working for $change_id: nr $count of $total.\t$dif\n";
}
$dbh->disconnect if defined($dbh);
