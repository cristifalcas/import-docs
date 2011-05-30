#!/usr/bin/perl -w
print "Start.\n";
use warnings;
use strict;
$SIG{__WARN__} = sub { die @_ };

#syncronize wiki with local fs: delete all in only one of them
#fix missing files: find pages with missing files, search for the pages on local dirs and remove them from both

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

use lib (fileparse(abs_path($0), qr/\.[^.]*/))[1]."./our_perl_lib/lib";
use Data::Dumper;
$Data::Dumper::Sortkeys = 1;
use File::Path qw(remove_tree);
use DBI;
use HTML::TreeBuilder::XPath;
use Encode;
use POSIX;
use Date::Calc qw(:all);

use Mind_work::WikiWork;
use Mind_work::WikiCommons;

my $dbh;
my $workdir = "/media/share/Documentation/cfalcas/q/import_docs/work/";
my $our_wiki;
$our_wiki = new WikiWork();
my ($local_pages, $wiki_pages);
my $view_only = shift;
$view_only = 1 if ! defined $view_only;
my $max_elements = 2000;

sub fixnamespaces {
  my $namespaces = shift;
  my $res = {};
  foreach my $ns_nr (keys %$namespaces){
    if ($ns_nr >= 100) {
	my $name = $namespaces->{$ns_nr};
	$name =~ s/ /_/g;
	if ($name =~ m/^(SC_|CRM_)/) {
	    $res->{'real'}->{$name} = $ns_nr;
	} elsif ($name =~ m/^(SC|CRM)$/) {
	    $res->{'redir'}->{$name} = $ns_nr;
	} else {
	    $res->{'normal'}->{$name} = $ns_nr;
	}
    } else {
	$res->{'private'}->{$namespaces->{$ns_nr}} = $ns_nr;
    }
  }

  return $res;
}

sub get_results {
  my ($link, $type) = @_;
  $type = "list" if !defined $type;
  my $regexp = "";
  if ($type eq "list" ){
    $regexp = q{/html/body/div[@id="content"]/div[@id="bodyContent"]/div[@class="mw-spcontent"]/ol/li/a/@title};
  } elsif ($type eq "ul" ){
    $regexp = q{/html/body/div[@id="content"]/div[@id="bodyContent"]/div[@class="mw-spcontent"]/ul[@class="gallery"]/li/div/div/div/a/img/@alt};
  } elsif ($type eq "table" ){
    $regexp = q{/html/body/div[@id="content"]/div[@id="bodyContent"]/div[@class="mw-spcontent"]/table[@class="gallery"]/tr/td/div[@class="gallerybox"]/div[@class="gallerytext"]/a/@title};
  } else {
    die "Unknown type: $type.\n";
  }
  my @res;
  my $file_res = WikiCommons::http_get("$link");
  my $tree= HTML::TreeBuilder::XPath->new;
  $file_res = Encode::decode("utf8", $file_res);
  $tree->parse( "$file_res");
  foreach my $result ($tree->findnodes_as_strings($regexp)) {
        push @res, $result;
  }
  $tree->delete;
  return \@res;
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

sub sql_get_crm_info_for_user {
  my $name = shift;
#   print "$name\n";
  my @names = split (/\./, $name);
  die "numele nu stiu ce sa fac cu el: $name.\n" if @names != 2;

  my $SEL_MODULES = "
select t.rscmainrecsubject,
       t.rscmainrecscno,
       a.rcustcompanycode,
       a.rcustiddisplay,
       t.rscmainreclasteventdate,
       rscmainrecservicestatus,
       s.rsctypesdesc
  from tblscmainrecord      t,
       tblcustomers         a,
       tblsuppdept          b,
       tbldeptsforcustomers c,
       (select w.rsctypescode, w.rsctypesdesc
          from tblsctypes w
        union
        select 0, ' ' from dual)           s,
       tblsupportstaff      q
 where rscmainrecservicestatus not in ('CCC', 'cld')
   and t.rscmainreccustcode = a.rcustcompanycode
   and a.rcustcompanycode = c.rdeptcustcompanycode
   and b.rsuppdeptcode = c.rdeptcustdeptcode
   and c.rcuststatus = 'A'
   and a.rcuststatus = 'A'
   and b.rsuppdeptstatus = 'A'
   and c.ractivitydate = (select max(ractivitydate)
                            from tbldeptsforcustomers
                           where rdeptcustcompanycode = a.rcustcompanycode
                             and rcuststatus = 'A')
   and rscmainrecenggincharge = q.rsuppstaffenggcode
   and s.rsctypescode = t.rscmainrecsctype
   and lower(q.rsuppstafflastname) = '".lc($names[1])."'
   and lower(rsuppstafffirstname) = '".lc($names[0])."'
 order by 1";
  my $sth = $dbh->prepare($SEL_MODULES);
  $sth->execute();
  my $info = {};
  my $i = 0;
  while ( my @row=$sth->fetchrow_array() ) {
      die "too many rows for table.\n" if @row != 7;
      $info->{$i}->{'subj'} = $row[0];
      $info->{$i}->{'sc_no'} = $row[1];
      $info->{$i}->{'comp_code'} = $row[2];
      $info->{$i}->{'cust_disp'} = $row[3];
      $info->{$i}->{'last_event'} = $row[4];
      $info->{$i}->{'status'} = $row[5];
      $info->{$i}->{'type'} = $row[6];
#       $info->{$i}->{'type'} = "q";
      $i++;
  }

  foreach my $j (keys %$info) {
      $SEL_MODULES = "
select rscrefnum1, rscrefnum2
  from tblscrefnum w
 where w.rscrefcust = ".$info->{$j}->{'comp_code'}."
   and w.rscrefscno = ".$info->{$j}->{'sc_no'}."
   and (REGEXP_LIKE(w.rscrefnum1, '[a-zA-Z][0-9]{1,}') or
       REGEXP_LIKE(w.rscrefnum2, '[a-zA-Z][0-9]{1,}'))";
      my $sth = $dbh->prepare($SEL_MODULES);
      $sth->execute();
      while ( my @row=$sth->fetchrow_array() ) {
	  die "too many rows for table.\n" if @row != 2;
# 	  $info->{$j}->{'bug1'} = $row[0] if $row[0] !~ m/^\s*$/;
# 	  $info->{$j}->{'bug2'} = $row[1] if $row[1] !~ m/^\s*$/;
# print Dumper( $j, $row[0],  $row[1]);
	  $info->{$j}->{'bug'}->{$row[0]} = 1 if $row[0] =~ m/^\s*[a-z][0-9]{1,}\s*$/i;
	  $info->{$j}->{'bug'}->{$row[1]} = 1 if $row[1] =~ m/^\s*[a-z][0-9]{1,}\s*$/i;
      }
  }
# print Dumper($info);
  return $info;
}

sub sql_get_sc_info_for_user {
  my $name = shift;
  my $id = "";

  my $SEL_MODULES = "select id from scwork where lower(workername)='".lc($name)."'";
  my $sth = $dbh->prepare($SEL_MODULES);
  $sth->execute();
  while ( my @row=$sth->fetchrow_array() ) {
      die "too many rows for table.\n" if @row > 1;
      $id = $row[0];
      last;
  }

  $SEL_MODULES =
'select column_name
  from all_tab_columns
 where table_name = upper(\'scchange\')
   and (column_name like upper(\'%incharge\') or
       column_name like upper(\'%leader\') or
       column_name = upper(\'initiator\'))';
  $sth = $dbh->prepare($SEL_MODULES);
  $sth->execute();
  my @rows = ();
  while ( my @row = $sth->fetchrow_array() ) {
      die "too many rows for table.\n" if @row > 1;
      push @rows, $row[0]."='$id'";
  }

  $SEL_MODULES =
"select changeid, title, status
  from scchange s
 where lower(status) not in ('prod', 'cancel', 'inform-cancel', 'suspended', 'develop-close', 'not released', 'documentation')
   and (".(join ' or ', @rows).")
 order by 1";
  $sth = $dbh->prepare($SEL_MODULES);
  $sth->execute();
  my $info = {};
  my $i = 0;
  while ( my @row = $sth->fetchrow_array() ) {
      die "too many rows for select.\n" if @row > 3;
      $info->{$i}->{'id'} = $row[0];
      $info->{$i}->{'title'} = $row[1];
      $info->{$i}->{'status'} = $row[2];
      $i++;
  }
  return $info;
}

sub make_sc_table {
    my $info_sc = shift;
    my $open_bugs = {};
    my $table_sc = {};
    my $table = '{| class="sortable wikitable"
|- style="background: #DDFFDD;"
! SC id
| Description
| Status';
    my $table_rows = {};
    foreach my $sc (keys %$info_sc) {
	### opened bugs
	$open_bugs->{$info_sc->{$sc}->{'id'}} = 1;
	$table_rows->{$info_sc->{$sc}->{'id'}} = "\n|-
| [[SC:".$info_sc->{$sc}->{'id'}."|".$info_sc->{$sc}->{'id'}."]]
| ".$info_sc->{$sc}->{'title'}."
| ".$info_sc->{$sc}->{'status'};
    }
    my $tmp = "";
    $tmp .= $table_rows->{$_} foreach (sort keys %$table_rows);
    $table_sc = $table.$tmp."\n|}\n" if $tmp ne "";
    return ("\n==Bugs opened==\n\n".$table_sc, $open_bugs);
}

sub make_crm_table {
    my ($info_crm, $open_bugs) = @_;
    my $url_sep = WikiCommons::get_urlsep;
    my ($too_old, $bug_closed, $normal, $too_aac) = {};

    my $table = '{| class="sortable wikitable"
|- style="background: #DDFFDD;"
! Age
| Description
| Status
| Type
| Customer';
    foreach my $crm (keys %$info_crm) {
# 	  my $two_weeks_ago = `date -d "14 days ago" +%Y%m%d`;
	my $event_date = $info_crm->{$crm}->{'last_event'};
	my @timeData = localtime(time);
	my ($event_year, $event_month, $event_day) = ((substr $event_date, 0, 4), (substr $event_date, 4, 2), (substr $event_date, 6, 2));
	my ($crt_year, $crt_month, $crt_day) = ($timeData[5]+1900, $timeData[4]+1, $timeData[3]);
	my $diff = Delta_Days($event_year, $event_month, $event_day,$crt_year, $crt_month, $crt_day);
	my $diff_txt = $diff." days";
	if ($diff>30) {
	    $diff_txt = sprintf "%.0f weeks",($diff / 7);
	}
	## we will ignore bug2
	my $table_row = "\n|-
| $diff_txt
| [[CRM:".$info_crm->{$crm}->{'cust_disp'}."$url_sep".$info_crm->{$crm}->{'sc_no'}."|".$info_crm->{$crm}->{'subj'}."]]
| ".$info_crm->{$crm}->{'status'}."
| ".$info_crm->{$crm}->{'type'}."
| [[:Category:$info_crm->{$crm}->{'cust_disp'}|$info_crm->{$crm}->{'cust_disp'}]] / $info_crm->{$crm}->{'sc_no'}";
# print Dumper($info_crm);exit 1;
	my $closed_bug = 0;
	foreach (keys %{$info_crm->{$crm}->{'bug'}}) {
	  if (! defined $open_bugs->{$_}) {
	    $closed_bug++;
	    last;
	  }
	}
	if ($diff > 30 && $info_crm->{$crm}->{'status'} eq "AAC") {
	    $too_aac->{$info_crm->{$crm}->{'subj'}} = $table_row;
	} elsif ($info_crm->{$crm}->{'status'} eq "AAC") {
	    ### skip all other AAC
	} elsif ($closed_bug) {
	    $bug_closed->{$info_crm->{$crm}->{'subj'}} = $table_row;
	} elsif ($diff > 14 && $info_crm->{$crm}->{'status'} eq "WFI") {
	    $too_old->{$info_crm->{$crm}->{'subj'}} = $table_row;
	} else {
	    $normal->{$info_crm->{$crm}->{'subj'}} = $table_row;
	}
    }

    my $new_txt = "";

    my $tmp = "";
    $tmp .= $normal->{$_} foreach (sort keys %$normal);
    $new_txt .= "\n==SRs==\n\n".$table.$tmp."\n|}\n" if $tmp ne "";

    $tmp = "";
    $tmp .= $too_old->{$_} foreach (sort keys %$too_old);
    $new_txt .= "\n==SRs too old==\n\n".$table.$tmp."\n|}\n" if $tmp ne "";

    $tmp = "";
    $tmp .= $too_aac->{$_} foreach (sort keys %$too_aac);
    $new_txt .= "\n==SRs closed too old==\n\n".$table.$tmp."\n|}\n" if $tmp ne "";

    $tmp = "";
    $tmp .= $bug_closed->{$_} foreach (sort keys %$bug_closed);
    $new_txt .= "\n==SRs with closed bugs==\n\n".$table.$tmp."\n|}\n" if $tmp ne "";

    return $new_txt;
}

sub update_user_pages {
  my $users_ns = shift;
  my $section_name = "=Open tasks=";
  my $pages = $our_wiki->wiki_get_all_pages($users_ns);

  foreach my $user_page (@$pages) {
      my $name = $user_page;
      $name =~ s/User://gi;
      my $txt = $our_wiki->wiki_get_page($user_page)->{'*'};
      my $new_txt = $txt;
      $new_txt =~ s/(\n|^)$section_name\s*(\n.*|$)//gsi;
      next if $new_txt eq $txt;

      sql_connect('10.0.0.103', 'SCROM', 'scview', 'scview');
      my $info_sc = sql_get_sc_info_for_user($name);
      $dbh->disconnect if defined($dbh);

      sql_connect('10.0.10.92', 'BILL', 'service25', 'service25');
      my $info_crm = sql_get_crm_info_for_user($name);
      $dbh->disconnect if defined($dbh);

      my ($table_sc, $open_bugs) = make_sc_table($info_sc);
      my $table_crm = make_crm_table($info_crm, $open_bugs);

      $new_txt .= "\n$section_name\n\n";
      $new_txt .= $table_crm if $table_crm ne "";
      $new_txt .= $table_sc if $table_sc ne "";

#       print "Writing page $user_page.\n";
      $our_wiki->wiki_edit_page($user_page, $new_txt);
  }
}

sub fix_wiki_sc_type {
  my $namespaces = shift;
  my $array = ();
  my $hash = $namespaces->{'redir'};
  foreach my $ns (keys %$hash){
    $array = $our_wiki->wiki_get_nonredirects("$hash->{$ns}");
    print "Found ". (scalar @$array) . " pages in namespace $ns.\n" if defined $array;
    foreach my $url (@$array) {
      print "rm redir page $url\n";
      $our_wiki->wiki_delete_page($url) if ( ! $view_only && $our_wiki->wiki_exists_page("$url") );
    }
  }

  $hash = $namespaces->{'real'};
  foreach my $ns (keys %$hash){
    $array = $our_wiki->wiki_get_redirects("$hash->{$ns}");
    print "Found ". (scalar @$array) . " pages in namespace $ns.\n" if defined $array;
    foreach my $url (@$array) {
      print "rm real page $url\n";
      $our_wiki->wiki_delete_page($url) if ( ! $view_only && $our_wiki->wiki_exists_page("$url") );
    }
  }

}

sub unused_categories {
    my $all_categories = $our_wiki->wiki_get_categories();
    my $result = ();
    foreach my $cat (@$all_categories) {
	my $res = $our_wiki->wiki_get_pages_in_category($cat, 1);
	next if defined $res;
	push @$result, $cat;
# 	print "rm page $cat\n";
# 	$our_wiki->wiki_delete_page($cat) if ( $our_wiki->wiki_exists_page("$cat") && ! $view_only);
    }
    return $result;
}

sub wanted_categories {
  my $link = "http://localhost/wiki/index.php?title=Special:WantedCategories&limit=$max_elements&offset=0";
  my $res = get_results($link);
  my $result = ();
  foreach my $elem (@$res){
      $elem =~ s/ \(page does not exist\)$//;
      my $cat = "Category:$elem";
      push @$result, $cat;
#       print "add category $cat.\n";
#       $our_wiki->wiki_edit_page("$cat", "----") if ! $view_only;
  }
  return $result;
}

sub broken_redirects {
  my $link = "http://localhost/wiki/index.php?title=Special:BrokenRedirects&limit=$max_elements&offset=0";
  my $res = get_results($link);
  my $seen = {};
  foreach my $elem (@$res){
    next if $seen->{$elem};
    $elem =~ s/ \(page does not exist\)$//;
    $seen->{$elem} = 1;
    print "rm page $elem.\n";
    $our_wiki->wiki_delete_page($elem) if ( $our_wiki->wiki_exists_page("$elem") && ! $view_only);
  }
}

sub scdoubleredirects {
  my $link = "http://localhost/wiki/index.php?title=Special:DoubleRedirects&limit=$max_elements&offset=0";
  my $res = get_results($link);
  my $seen = {};
  foreach my $elem (@$res){
    next if $seen->{$elem};
    $seen->{$elem} = 1;
    print "rm page $elem.\n";
    $our_wiki->wiki_delete_page($elem) if ( $our_wiki->wiki_exists_page("$elem") && ! $view_only);
  }
}

sub unused_images_dirty {
  my $link = "http://localhost/wiki/index.php?title=Special:UnusedFiles&limit=$max_elements&offset=0";
  my $res = get_results($link, "ul");
  foreach my $elem (@$res){
      $elem =~ s/%27/'/g;
      $elem =~ s/%26/&/g;
      print "rm file $elem.\n";
#       if (! $our_wiki->wiki_exists_page("$elem")) {
# 	print "add page \n\t$elem.\n";
# 	$our_wiki->wiki_edit_page("$elem", "----") if ( ! $view_only);
#       }
      $our_wiki->wiki_delete_page("File:$elem") if ! $view_only;
  }
}

sub fix_wanted_pages {
  my $link = "http://localhost/wiki/index.php?title=Special:WantedPages&limit=$max_elements&offset=0";
  my $res = get_results($link);
  my ($cat, $sc, $crm, $other) = ();
  foreach my $elem (@$res){
      next if $elem eq "Special:WhatLinksHere";
      $elem =~ s/ \(page does not exist\)$//;
#       $elem =~ s/ /_/g;
#       print "$elem\n";#
      if ($elem =~ m/^SC:[A-Z][0-9]+$/) {
	push @$sc, $elem;
      } elsif ($elem =~ m/^CRM:[A-Z][0-9]+$/) {
	push @$crm, $elem;
      } elsif ($elem =~ m/^Category:/) {
	push @$cat, $elem;
      } else {
	push @$other, $elem;
      }
  }
  return ($cat, $sc, $crm, $other);
}

sub fix_missing_files {
    ## this will delete pages if the user forgot to add an image
  my $link = "http://localhost/wiki/index.php?title=Special:WantedFiles&limit=$max_elements&offset=0";
  my $res = get_results($link);
  my $missing = {};
  foreach my $elem (@$res){
    next if $elem eq "Special:WhatLinksHere";
    $elem =~ s/ \(page does not exist\)//;
    my $arr = $our_wiki->wiki_get_pages_using("$elem");
    foreach my $page (@$arr) {
	print "Get page $page for file $elem.\n";
	$missing->{$page} = 1;
    }
  }
  foreach my $page (keys %$missing) {
      next if $page eq "CMS:MIND-IPhonEX CMS 80.00.020" && $page !~ m/[a-b _]+:/i;
      print "rm page $page.\n";
      $our_wiki->wiki_delete_page($page) if ( $our_wiki->wiki_exists_page("$page") && ! $view_only);
  }
}

sub getlocalpages {
  my $namespaces = shift;

  my $local_pages = {};
  opendir(DIR, "$workdir") || die("Cannot open directory $workdir: $!.\n");
  my @alldirs = grep { (!/^\.\.?$/) && m/workfor/ && -d "$workdir/$_" } readdir(DIR);
  closedir(DIR);

  foreach my $adir (@alldirs) {
    opendir(DIR, "$workdir/$adir") || die("Cannot open directory $adir: $!.\n");
    print "Get local files from $adir: ";
    my $count = 0;
    foreach my $file (grep { (!/^\.\.?$/) && -d "$workdir/$adir/$_" } readdir(DIR)) {
      $count++;
      my $ns = "";
      my $normalyze_file = $file;
      if ( $file =~ m/^(.*?):(.*)$/ ) {
        $ns = $1;
	$normalyze_file = $2;
        $normalyze_file = WikiCommons::capitalize_string( $normalyze_file, 'onlyfirst' );
	$normalyze_file = "$ns:$normalyze_file";
      }
      $normalyze_file =~ s/ /_/g;
      if ($ns eq "") {
	$local_pages->{'private'}->{$normalyze_file} = "$adir/$file";
      } elsif ( defined $namespaces->{'redir'}->{$ns} ){
	$local_pages->{'redir'}->{$normalyze_file} = "$adir/$file";
      } elsif ( defined $namespaces->{'real'}->{$ns} ){
	$local_pages->{'real'}->{$normalyze_file} = "$adir/$file";
      } elsif ( defined $namespaces->{'normal'}->{$ns} ){
	$local_pages->{'normal'}->{$normalyze_file} = "$adir/$file";
      }
    }
    closedir(DIR);
    print "$count\n";
  }
  return $local_pages;
}

sub getlocalimages {
  our $namespaces = shift;
  use File::Find;
  our $local_pages = {};
  print "Get local images.\n";
  our $count = 0;
  sub process_file {
      my ($file, $full_path) = @_;
      $count++;
      $local_pages->{$file} = "$full_path";
#       die if $count >10;
  };

  my $images_dir = "/var/www/html/wiki/images/";
  opendir(DIR, "$images_dir") || die("Cannot open directory $images_dir: $!.\n");
  my @alldirs = grep { (!/^\.\.?$/) && m/^.$/ && -d "$images_dir/$_" } readdir(DIR);
  closedir(DIR);
  foreach my $dir (@alldirs) {
    eval {find ({wanted => sub { process_file ($_,$File::Find::name) if -f $_ },}, "$images_dir/$dir")};
  }

  return $local_pages;
}

sub getdbimages {
  use DBI;
  my $files = {};
  my $db = DBI->connect('DBI:mysql:wikidb', 'wikiuser', '!0wikiuser@9') || die "Could not connect to database: $DBI::errstr";
  my $sql_query="select distinct il_to from imagelinks";
  my $query = $db->prepare($sql_query);
  $query->execute();
  while (my ($file) = $query->fetchrow_array ){
    $files->{"$file"} = 1;
  }
  return $files;
}

sub getwikipages {
  my $namespaces = shift;

  my $wiki_pages = {};
  my @arr = ();
  foreach my $nstype (keys %$namespaces) {
    next if $nstype eq "private";
    print "Get wiki pages from $nstype.\n";
    my $tmp = $namespaces->{$nstype};
    @arr = ();
    foreach my $ns (keys %$tmp) {
      my $def = $our_wiki->wiki_get_all_pages($namespaces->{$nstype}->{$ns});
      foreach my $page (@$def) { 
	if (defined $page) {
	    $page =~ s/ /_/g;
	    push @arr, "$page";
	} 
      };
    }
    my %hash = map { $_ => 1 } @arr;
    $wiki_pages->{$nstype} = \%hash;
  }
  return $wiki_pages;
}

sub syncronize_local_wiki {
    for my $tmp ('redir', 'real', 'normal'){
	my $hash1 = $local_pages->{$tmp};
	my $hash2 = $wiki_pages->{$tmp};
	my @arr1 = (sort keys %$hash1);
	my @arr2 = (sort keys %$hash2);
	my ($only_in1, $only_in2, $common) = WikiCommons::array_diff( \@arr1, \@arr2 );
	print "$tmp only in local: ".Dumper($only_in1); print "$tmp only in wiki: ".Dumper($only_in2);
	die "Too many to delete: in local = ".(scalar @$only_in1)." in wiki = ".(scalar @$only_in2).".\n" if scalar @$only_in1 > 200 || scalar @$only_in2 > 200;
	foreach my $local (@$only_in1) {
	    print "rm dir $workdir/$local_pages->{$tmp}->{$local}\n";
	    if ( ! $view_only ) {
		remove_tree("$workdir/$local_pages->{$tmp}->{$local}") || die "Can't remove dir $workdir/$local_pages->{$tmp}->{$local}: $?.\n";
	    }
	    delete $local_pages->{$tmp}->{$local};
	}
	foreach my $wiki (@$only_in2) {
	    print "rm page $wiki\n";
	    $our_wiki->wiki_delete_page($wiki) if ( $our_wiki->wiki_exists_page("$wiki") && ! $view_only);
	    delete $wiki_pages->{$tmp}->{$wiki};
	}
    }
}

sub fix_images {
  my $namespaces = shift;

  my $wiki_images = $our_wiki->wiki_get_all_images();
  my $local_images = getlocalimages($namespaces);
  my @local_images = keys %$local_images;
#   my $db_images = getdbimages;
#   my @db_images = keys %$db_images;

#   my ($only_in1, $only_in2, $common) = WikiCommons::array_diff( \@db_images, $wiki_images);
#   ## Files are not imported for those, but are used (missing files):
#   print Dumper($only_in1);
#   ## Nobody links here (unused files):
#   print Dumper($only_in2);

  my ($only_in_wiki, $only_in_fs, $common_all) = WikiCommons::array_diff( $wiki_images, \@local_images);
  ## Files are missing from the fs
  print Dumper($only_in_wiki);
  ## Files found here are not used
  print Dumper($only_in_fs);
}

if ( -f "new 1.txt" ) {
    open(DAT, "new 1.txt") || die("Could not open file!");
    my @raw_data=<DAT>;
    chomp @raw_data;
    close(DAT);
    foreach my $w (@raw_data) {
	my $q = $our_wiki->wiki_get_pages_linking_to("$w");
	print "$w\n";
# 	print Dumper($q);next;
	foreach my $e (@$q){
	    $our_wiki->wiki_delete_page($e);
	}
    }
}

my $namespaces = $our_wiki->wiki_get_namespaces;
$namespaces = fixnamespaces($namespaces);

# # print Dumper($namespaces);
print "##### Update users:\n";
update_user_pages($namespaces->{'private'}->{'User'});
print "##### Fix wiki sc type:\n";
fix_wiki_sc_type($namespaces);
print "##### Fix broken redirects:\n";
broken_redirects;
print "##### Fix double redirects:\n";
scdoubleredirects;
print "##### Fix missing files:\n";
fix_missing_files();
print "##### Remove unused images:\n";
unused_images_dirty;
# print "##### Wanted pages:\n";
# my ($cat, $sc, $crm, $other) = fix_wanted_pages();
# print "##### Get unused categories:\n";
# my $unused = unused_categories();
# print "##### Get missing categories:\n";
# my $wanted = wanted_categories();
print "##### Syncronize wiki files with fs files.\n";
# fix_images($namespaces);
print "##### Syncronize:\n";
$local_pages = getlocalpages($namespaces);
$wiki_pages = getwikipages($namespaces);
syncronize_local_wiki;

# compressOld.php

## all files deleted deleteArchivedFiles.php
# rm -rf /media/share/wiki_images/deleted/*
# delete from filearchive;
## all files overwriten
# rm -rf /media/share/wiki_images/archive/*
# oldimage by oi_timestamp

## all pages deleted: deleteArchivedRevisions.php
# archive ar_namespace, ar_title
## holds the wikitext of individual page revisions: PurgeOldText.php
# text
## holds metadata for every edit done to a page
# revision

# my $q = $our_wiki->wiki_get_all_categories(14);
# print Dumper($q);
