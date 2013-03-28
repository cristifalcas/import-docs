#!/usr/bin/perl -w
use warnings;
use strict;
$SIG{__WARN__} = sub { die @_ };
$| = 1;

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

my $path_prefix = (fileparse(abs_path($0), qr/\.[^.]*/))[1]."";
use lib (fileparse(abs_path($0), qr/\.[^.]*/))[1]."/our_perl_lib/lib"; 
use Cwd 'abs_path';
use File::Basename;
use File::Copy;
use File::Find;
use File::Path qw(make_path remove_tree);
use Getopt::Std;
use lib (fileparse(abs_path($0), qr/\.[^.]*/))[1]."our_perl_lib/lib";
use MIME::Base64;
use Email::MIME;
use Data::Dumper;
use HTML::TreeBuilder;
use DBI;
use Encode;
use Storable;
use URI::Escape;

use Mind_work::WikiCommons;

use Log::Log4perl qw(:easy);
Log::Log4perl->easy_init( { level   => $DEBUG,
			    layout   => "%d [%5p] (%6P) - %m{chomp}\n", } );
use Getopt::Std;
my $options = {};
getopts("d:t:", $options); 

my ($tmp_path, $to_path) = ($options->{t}, $options->{d});
LOGDIE "We need temp dir and result dir.\n" if ! defined $tmp_path || ! defined $to_path;

my $dbh;

sub oracle_connenct {
    ### connect to oracle
    $ENV{NLS_LANG} = 'AMERICAN_AMERICA.AL32UTF8';
    my ($ip, $sid, $user, $pass) = ('10.10.16.5', 'OTRS', 'otrsweb', 'cascade');
    $dbh=DBI->connect("dbi:Oracle:host=$ip;sid=$sid;port=1521", "$user/$pass")|| die( $DBI::errstr . "\n" );
    $dbh->{AutoCommit}    = 1;
    $dbh->{RaiseError}    = 1;
    $dbh->{ora_check_sql} = 0;
    $dbh->{RowCacheSize}  = 16;
    $dbh->{LongReadLen}   = 52428800;
    $dbh->{LongTruncOk}   = 0;
    $dbh->{FetchHashKeyName}   = 'NAME_lc';
     DEBUG "connected to oracle\n";
}

# sub from_email {
#     my $decoded = shift;
#     my $parsed = Email::MIME->new($decoded);
#     handle_parts($parsed);
# 
#     our $info;
# 
#     sub get_content_id {
# 	my $part = shift;
# 	my $content_id = "";
# 	my @headers = @{$part->{header}->{headers}};
# 	while (scalar @headers) {
# 	    my $key = shift @headers;
# 	    if ($key eq "Content-ID"){
# 		$content_id = shift @headers;
# 		return $content_id;
# 	    }
# 	}
# 	return $content_id;
#     }
# 
#     sub handle_parts {
# 	my $part = shift;
# 	my $content_type = $part->content_type;
# 	my $body = $part->body;
# 	
# 	if ($content_type =~ m#text/plain#) {
# 	    print "1. text/plain\n";
# 	    die "coco\n" if defined $info->{text};
# 	    $info->{text} = $body;
# 	} elsif ($content_type =~ m#text/html#) {
# 	    print "2. text/html\n";
# 	    die "coco\n" if defined $info->{html};
# 	    $info->{html} = $body;
# 	} elsif ($content_type =~ m#image/#) {
# 	    my $file_name = $part->filename || "";
# 	    my $c_id = get_content_id($part);
# 	    print "3. image/ $file_name => $c_id\n";
# 	    die "coco\n" if defined $info->{image}->{$file_name};
# 	    $info->{image}->{$file_name}->{content_id} = $c_id;
# 	    $info->{image}->{$file_name}->{content} = $body;
# 	} elsif ($content_type =~ m#multipart/#) {
# 	    handle_parts($_) foreach ($part->parts);
# 	} elsif ($content_type =~ m#application/octet-stream#) {
# 	    die "4. application/octet-stream\n";
# 	} else {
# 	    die "N. unknown: $content_type\n";
# 	}
#     }
#     die "buhuhu\n" if ! defined $info->{html};
#     return $info->{html};
# }

sub tree_clean_headings {
    my $tree = shift;
    INFO "Fix headings.\n";

    foreach my $a_tag ($tree->descendants()) {
	if ($a_tag->tag =~ m/^h[0-9]{1,2}$/){
	    $a_tag->tag("b");
	    $a_tag->postinsert(['br']);
	    $a_tag->postinsert(['br']);
	    $a_tag->preinsert(['br']);
	    $a_tag->preinsert(['br']);
	}
    }
    return $tree;
}

sub tree_clean_div_cite {
    my ($tree) = @_;
    INFO "Clean cite.\n";
    foreach my $a_tag ($tree->guts->look_down(_tag => "div")) {
	foreach my $attr_name ($a_tag->all_external_attr_names){
	    my $attr_value = $a_tag->attr($attr_name);
	    next if $attr_name ne "type";
	    $a_tag->detach;
	    last;
	}
    }
    return $tree;
}

sub tree_fix_images {
    my ($tree, $images) = @_;
    INFO "Fix images inline.\n";
    foreach my $a_tag ($tree->guts->look_down(_tag => "img")) {
	my ($width, $height, $name_img);
	foreach my $attr_name ($a_tag->all_external_attr_names){
	    $name_img = undef;
	    my $attr_value = $a_tag->attr($attr_name);
	    if ($attr_name eq "src") {
		$name_img = uri_unescape($a_tag->attr($attr_name));
		next if $name_img =~m#https?://#i; ## external images
		die "unknown img: $name_img.\n".($tree->guts->as_HTML(undef, "\t")) if ! defined $images->{$name_img};
		my $file_name = $images->{$name_img}->{filename};
		$a_tag->attr($attr_name, $file_name);
	    } elsif ($attr_name eq "style") {
# 		my @values = split ";", $attr_value;
# 		foreach (@values) {
# 		    $height = $1 if $_ =~ m/^ *height: +([0-9]+[a-z]+) *$/i;
# 		    $width = $1 if $_ =~ m/^ *width: +([0-9]+[a-z]+) *$/i;
# 		}
# 	    } elsif ($attr_name eq "height") {
# 		$height = $attr_value;
# 	    } elsif ($attr_name eq "width") {
# 		$width = $attr_value;
	    }
	}
# 	next if ! defined $name_img;
# 	$images->{$name_img}->{height} = $height;
# 	$images->{$name_img}->{width} = $width;
    }
    return $tree;
}

sub parse_html {
    my ($html, $images) = @_;
    my $tree = HTML::TreeBuilder->new(); 
    $tree->no_space_compacting(1);
    $tree = $tree->parse_content(decode_utf8($html)); 
    $tree = tree_clean_div_cite($tree);
    $tree = tree_clean_headings($tree);
    $tree = tree_fix_images($tree, $images);
    my $html_res = $tree->guts ? $tree->guts->as_HTML(undef, "\t") : "";
    $tree = $tree->delete; 
    return Encode::encode('utf8', $html_res); 
}

sub get_all_tickets {
    my $SEL_CHANGES = "
select t.id,
       t.tn,
       t.title,
       t.type_id,
       t.service_id,
       t.sla_id,
       t.user_id,
       t.ticket_priority_id,
       t.ticket_state_id,
       t.customer_id,
       t.create_time,
       t.change_time,
       t.change_by,
       count(*) nr_articles
  from ticket t, ARTICLE a
 where t.id = a.ticket_id
 group by t.id,
          t.tn,
          t.title,
          t.type_id,
          t.service_id,
          t.sla_id,
          t.user_id,
          t.ticket_priority_id,
          t.ticket_state_id,
          t.customer_id,
          t.create_time,
          t.change_time,
          t.change_by";
    my $hash = $dbh->selectall_hashref($SEL_CHANGES, ['id']);
store $hash, "__save_hash_tickets";
    return $hash;
}

sub get_ticket_info {
    my $ticket_id = shift;
    my $SEL_CHANGES = "
    select a.id art_id,
       aa.id attch_id,
       a.article_type_id,
       a.article_sender_type_id,
       a.a_from,
       a.a_to,
       a.a_cc,
       a.a_subject,
       a.a_references,
       a.change_by,
       aa.filename,
       aa.content_type,
       aa.content_id,
       aa.content
  from article_attachment aa, ARTICLE a
 where a.ticket_id = $ticket_id
   and a.id = aa.article_id";

    my $hash = $dbh->selectall_hashref($SEL_CHANGES, ['art_id', 'attch_id']);
store $hash, "__save_hash_$ticket_id";
    return $hash;
}

sub format_info {
    my $hash_art = shift;
    my ($text, $images, $attachements);

    foreach my $attachment_id (keys %$hash_art) {
	my $hash = $hash_art->{$attachment_id};
	my $content = decode_base64($hash->{content});
	die "no content\n" if ! defined $content;

	my $filename = $hash->{filename};
	my $content_id = $hash->{content_id};
	my $content_type = $hash->{content_type};

	if( $filename eq "file-2" && $content_type eq 'text/html; charset="utf-8"') {
	    die "double text\n" if defined $text;
	    $text = $content;
	} elsif ($content_type =~ m/^image\// && defined $content_id) {
	    if (! defined $content_id) {
		print "bla no c_id\n";
		next;
	    }
	    $content_id =~ s/(^<)|(>$)//g;
	    $content_id = "cid:".$content_id;
	    die "image already exists\n" if defined $images->{$content_id};
	    $images->{$content_id}->{body} =  $content;
	    my ($name,$dir,$suffix) = fileparse($filename, qr/\.[^.]*/);
	    $images->{$content_id}->{filename} =  "$name.png";
	    $images->{$content_id}->{filename_orig} =  $filename;
	} else {
	    $attachements->{$filename} = $content;
	}
    }
    die "no text\n" if ! defined $text;
    return ($text, $images, $attachements);
}

sub write_files {
    my ($html, $images, $attachements, $work_dir) = @_;
    my $fh;
    open($fh, ">:utf8", "$work_dir/page.html");
    print $fh $html;
    close($fh);

    foreach my $c_id (keys %$images) {
	open($fh, '>:raw', "$work_dir/$images->{$c_id}->{filename_orig}") or die "Unable to open: $!";
	print $fh $images->{$c_id}->{body};
	close($fh);
	if ($images->{$c_id}->{filename_orig} ne $images->{$c_id}->{filename}) {
	    system("convert", "$work_dir/$images->{$c_id}->{filename_orig}", "-background", "white", "-flatten", "$work_dir/$images->{$c_id}->{filename}") == 0 or LOGDIE "error runnig convert: $!.\n\t$images->{$c_id}->{filename_orig} ne $images->{$c_id}->{filename}\n";
	    unlink "$work_dir/$images->{$c_id}->{filename_orig}";
	}
    }

    foreach my $filename (keys %$attachements) {
	open($fh, '>:raw', "$work_dir/attachements/$filename") or die "Unable to open: $!";
	print $fh $attachements->{$filename};
	close($fh);
    }
}

sub write_ticket {
    my $ticket_id = shift;
#     my $hash = get_ticket_info($ticket_id);
    my $hash = retrieve('__save_hash_471');

    foreach my $art_id (sort {$a <=> $b} keys %$hash) {
	my $work_dir = "$tmp_path/$ticket_id/$art_id";
	remove_tree($work_dir);
	make_path("$work_dir/attachements");
	my ($html, $images, $attachements) = format_info($hash->{$art_id});
	$html = parse_html($html, $images);
	write_files($html, $images, $attachements, $work_dir);

## in insert
# 	WikiCommons::set_real_path($path_prefix);
# 	WikiCommons::generate_html_file( "$work_dir/page.html", "odt_macro", "mindserve_$ticket_id\_$art_id" ); 
# 	copy ("$work_dir/page.odt", "$tmp_path/$ticket_id/test_page_$art_id.odt") || LOGDIE "Can't copy odt: $!.\n";
    }
    remove_tree("$to_path/$ticket_id");
    make_path("$to_path/$ticket_id");
    move ("$tmp_path/$ticket_id/", "$to_path/$ticket_id") || LOGDIE "can't move: $!.\n";

}

# oracle_connenct();
# my $tickets = get_all_tickets();

my $tickets = retrieve('__save_hash_tickets');

remove_tree($tmp_path);
make_path($tmp_path);
make_path($to_path);

write_ticket(471);


# /index.pl?Action=AgentTicketAttachment;Subaction=HTMLView;ArticleID=1530;FileID=1
# http://www.mediawiki.org/wiki/Extension:Widget
# http://www.mediawikiwidgets.org/Iframe

# --https://mindserve.mindcti.com/index.pl?Action=AgentTicketZoom;TicketID=443;ArticleID=1752#1434
# --https://10.10.16.6           /index.pl?Action=AgentTicketZoom;TicketID=443;ArticleID=1432
# --https://10.10.16.6           /index.pl?Action=AgentTicketZoom;TicketID=448#1462




# <html>
# 	<head>
# 		<meta content="text/html; charset=utf-8" http-equiv="Content-Type" />
# 	</head>
# 	<body>
# 	.... my shit
# 	</body> 
# </html>

