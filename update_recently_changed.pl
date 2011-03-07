#!/usr/bin/perl -w

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

use DBI;
use lib (fileparse(abs_path($0), qr/\.[^.]*/))[1]."./our_perl_lib/lib";
use Mind_work::WikiWork;
my $our_wiki = new WikiWork();

my $wiki_page = '<div style="text-align: right;">'."\n";
# <div style=";font-size:80%">updated by [[User:Wiki auto import]]<br>on 20110218123142  </div>';
print "Connecting...\n";
my $db = DBI->connect('DBI:mysql:wikidb', 'wikiuser', '!0wikiuser@9') || die "Could not connect to database: $DBI::errstr"; 
print "Connected.\n";
# $db->selectdb($database);
my $sql_query="select rc_timestamp, rc_user_text, rc_title
  from recentchanges rc, page p
 where rc_title not in
       ('Test', 'Common.js', 'RecentlyModified', 'Main_Page', 
        'Test', 'Test1', 'Test2', 'SIP', 'Maintenance_on_wiki', 
    	'Automatically_import_documents_to_wiki')
   and rc_namespace = 0
   and rc.rc_title = p.page_title
   and rc_timestamp = (select max(rc_timestamp)
                         from recentchanges rcs
                        where rc_namespace = 0
                          and rcs.rc_title = rc.rc_title
                          and abs(rcs.rc_new_len - rcs.rc_old_len) > 100
                          /*and ((rc_new<>1 and rc_user_text <> 'Cristian.falcas'
                          and rc_user_text <> '10.0.6.78'
                          and rc_user_text <> '10.0.4.128') or rc_new=1)*/)
 group by rc_title
 order by rc_timestamp desc limit 10;";
print "Query...\n";
my $query = $db->prepare($sql_query); 
$query->execute();
my $max_size = 45;
while (my ($time, $user, $page) = $query->fetchrow_array ){
  my $new_page = $page;
  $new_page =~ s/_/\ /g;
  $new_page = substr($new_page,0,$max_size)."..." if length($new_page) > $max_size;
  my $year = substr($time,0,4);
  my $month = substr($time,4,2);
  my $day = substr($time,6,2);
  my $hour = substr($time,8,2);
  my $min = substr($time,10,2);
  my $sec = substr($time,12,2);
  my $new_time = "$day-$month-$year $hour:$min:$sec";
  my $entry = '<div style="float: left;">[['.$page.'|'.$new_page.']]</div><br>'."\n";
  $entry .= '<div style=";font-size:80%">updated by [[User:'.$user.'|'.$user.']] on '.$new_time.'</div>'."\n";
  $wiki_page .= $entry;
# print "$time: $year $month $day \n";
}

$wiki_page .= '</div>'."\n";
# print "$wiki_page";
$our_wiki->wiki_edit_page("Template:RecentlyModified", $wiki_page); 
print "Done.\n";

