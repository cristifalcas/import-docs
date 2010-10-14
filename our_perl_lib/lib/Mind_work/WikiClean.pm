package WikiClean;

use warnings;
use strict;

use File::Basename;
use URI::Escape;
use Image::Info qw(image_info dim);
use Mind_work::WikiCommons;
use Data::Dumper;
use Text::Balanced qw (
    extract_tagged
    extract_multiple
    gen_extract_tagged
    );
use Encode;

our $debug = "yes";

sub tag_remove_attr {
    my ($tag_name, $attr_name, $attr_value) = @_;
    if ($tag_name eq "font") {
	if ($attr_name eq "size" ||
	    $attr_name eq "face" ||
	    ($attr_name eq "style" && $attr_value =~ m/font-size: [0-9]{1,}pt/)) {
		return 1;
	    } elsif ($attr_name eq "color") {
		return 0;
	    } else {
		die "Unknown attribute for font: $attr_name = $attr_value.\n";
	    }
    } elsif ($tag_name eq "span"){
	    if ($attr_name eq "lang") {
		return 1;
	    } elsif ($attr_name eq "style" && (
		    $attr_value =~  m/background: #[a-f0-9]{6}/ ||
		    $attr_value =~  m/font-(weight|style): normal/ ) ) {
		return 0;
	    } else {
		die "Unknown attribute for span: $attr_name = $attr_value.\n";
	    }
    } else {
	die "Unknown attribute for tag $tag_name: $attr_name = $attr_value.\n";
    }
}

# sub is_empty {
#   my($font) = @_;
#
#   my $is_interesting = sub {
#     for ($_[0]->content_list) {
#       return 1 if !ref($_) && /\S/;
#     }
#   };
#
#   !$font->look_down($is_interesting);
# }

sub clean_empty_tag {
    my ($text, $tag) = @_;
# $text='<FONT COLOR="#000000"><IMG SRC="Viaero%20Configuration%20Guide_html_m2af2f4f1.png" NAME="graphics8" ALIGN=BOTTOM WIDTH=349 HEIGHT=340 BORDER=1></FONT>';
    my $tree = HTML::TreeBuilder->new_from_content(decode_utf8($text));
    foreach my $a_tag ($tree->guts->look_down(_tag => "$tag")) {
	next unless $a_tag->look_down(sub { grep !ref && /\S/ => $_[0]->content_list });
# 	if (my $q =$a_tag->look_down(sub { grep !ref && /\S/ => $_[0]->content_list })){
# # print Dumper($q);
# 	} else {
# $a_tag->detach;
#  next;
# 	}

	my $some_ok_attr = 0;
	my $tag_name = $a_tag->tag;
	for my $attr_name ($a_tag->all_external_attr_names){
	    my $attr_value = $a_tag->attr($attr_name);
	    if ( tag_remove_attr($tag_name, $attr_name, $attr_value) ) {
# print "rem attr $attr_name from tag $tag_name\n";
		$a_tag->attr("$attr_name", undef);
	    } else {
		++$some_ok_attr;
# print "keep attr $attr_name\n";
	    }
	}
# 	if ( ! $some_ok_attr ) {
# 	    $a_tag->replace_with($a_tag->content_list());
# print "replace tag $tag_name with ". Dumper($a_tag->content_list)."\n";
# 	}
	foreach my $text ($a_tag->content_refs_list) {
	    next if ref $$text;
# die "OK!!\n" if $$text =~ /m2af2f4f1/;
# 	    $$text =~ s/^\s+//;
# 	    $$text =~ s/\s+$//;
	}
    }
#     (my $cleaned = $tree->guts ? $tree->guts->as_HTML : "") =~ s/\s+$//;
    my $cleaned = $tree->guts ? $tree->guts->as_HTML(undef, "\t") : "";
# print "$cleaned\n";exit 1;
    return $cleaned;
}

sub html_clean_tables_in_menu {
    my $html = shift;
    print "\t-Fix in html tables in menus.\t". (WikiCommons::get_time_diff) ."\n";
    ## tables in menu
    my $count = 0;
    my $newhtml = $html;
    while ($html =~ m/(<h([0-9]{1,2})[^>]*>)(.*?)(<\/H\2>)/gsi ) {
	my $found_string = $&;
	my $found_string_end_pos = pos($html);
	my $start = $1; my $end = $4;
	my $text = $3; my $other = "";
	$text =~ s/<BR( [^>]*)?>//gsi;
	$text =~ s/(<B>)|(<\/B>)//gsi;
	$text =~ s/(<I>)|(<\/I>)//gsi;
	$text =~ s/(<CENTER( [^>]*)?>)|(<\/CENTER>)//gsi;
	$text =~ s/(<SDFIELD( [^>]*)?>)|(<\/SDFIELD>)//gsi;
# 	$text =~ s/<A [^>]*>.*?<\/A>//gsi;
	$text =~ s/(<SPAN( [^>]*)?>)|(<\/SPAN>)//gsi;
	$text =~ s/(<STRONG>)|(<\/STRONG>)//gsi;
	$text =~ s/(<EM>)|(<\/EM>)//gsi;
	if ($text =~ m/^(.*?)(<TABLE[^>]*>.*?<\/TABLE>)(.*?)$/si){
	    $text = "$1$3";
	    $other .= $2."\n";
	}
	while ($text =~ m/^(.*?)((<IMG SRC=[^>]*>\s*)+|(<P [^>]*>.*?<\/P>\s*)+)(.*?)$/si) {
	    $text = "$1$5\n";
	    $other .= $2."\n";
	}

	if ($text =~ m/(<([^>]*)>)/) {
	    die "shit menu in html: $text: $1\n" if ("$1" ne "<U>") && ("$1" ne "<SUP>") && ("$1" !~ m/<font[^>]*>/i) && ("$1" !~ m/<span[^>]*>/i) && ("$1" !~ m/<a name[^>]*>/i) && ("$1" !~ m/<STRIKE>/i) && ("$1" !~ m/<A [^>]*>/i);
	}
	my $replacement = "$start$text$end\n$other";
	substr($newhtml, $found_string_end_pos - length($found_string)+$count, length($found_string)) = "$replacement";
	$count += length($replacement) - length($found_string);
    }
    print "\t+Fix in html tables in menus.\t". (WikiCommons::get_time_diff) ."\n";
    return $newhtml;
}

sub html_clean_menu_in_tables {
    my $html = shift;
    print "\t-Fix in html menus in tables.\t". (WikiCommons::get_time_diff) ."\n";
    ## menus in tables
    my $count = 0;
    my $newhtml = $html;
    while ($html =~ m/(<TABLE[^>]*>)(.*?)(<\/TABLE>)/gsi ) {
	my $found_string = $&;
	my $found_string_end_pos = pos($html);
	my $start = $1; my $end = $3;
	my $text = $2;

	while ($text =~ m/(<h([0-9]{1,2})[^>]*>)(.*?)(<\/H\2>)/si) {
	    my $s = quotemeta $1; my $e = quotemeta $4;
	    $text =~ s/$s/<B>/;
	    $text =~ s/$e/<\/B>/;
	}
	my $replacement = "$start$text$end";
	substr($newhtml, $found_string_end_pos - length($found_string)+$count, length($found_string)) = "$replacement";
	$count += length($replacement) - length($found_string);
    }
    print "\t+Fix in html menus in tables.\t". (WikiCommons::get_time_diff) ."\n";
    return $newhtml;
}

sub html_clean_menu_in_lists {
    my $html = shift;
    print "\t-Fix in html menus in lists.\t". (WikiCommons::get_time_diff) ."\n";
    # fix menus from lists
    my $count = 0;
    my $newhtml = $html;
    my $extractor_h = gen_extract_tagged("<H[0-9]{1,2}[^>]*>", "<\/H[0-9]{1,2}>");
    print "\tExtract menus from lists.\t". (WikiCommons::get_time_diff) ."\n";
    while ($html =~ m/(<((OL)|(UL))[^>]*>)/gsi ) {
	my $found_string = $&;
	my $found_string_end_pos = pos($html);
	pos($html) -= length($found_string);
	my @type = ();
	if ($found_string =~ m/<OL/i) {
	    push @type, "<OL[^>]*>";
	    push @type, "<\/OL>";
	} elsif  ($found_string =~ m/<UL/i) {
	    push @type, "<UL[^>]*>";
	    push @type, "<\/UL>";
	} else {
	    die "blabla: $found_string\n";
	}
	my @data = extract_tagged( $html, "$type[0]", "$type[1]");
# 	pos($html) = $found_string_end_pos - length($found_string) + length($data[0]);
	next if $data[0] !~ m/(<H([0-9]{1,2})[^>]*>)(.*?)(<\/H\2>)/gsi;
	my $txt = $data[0];
	my @data_h = extract_multiple( $txt, [ $extractor_h]);
	print "\t\tdone.\t". (WikiCommons::get_time_diff) ."\n";

	my $titles = "";
	my $new_text = "";
	foreach my $h (@data_h) {
	    if ($h =~ m/^(<H[0-9]{1,2}[^>]*>.*?<\/H[0-9]{1,2}>)$/s) {
		$titles .= $h."\n";
	    } else {
		$new_text .= $h."\n";
	    }
	}
	$new_text = clean_empty_tag($new_text, "li");
	$new_text = clean_empty_tag($new_text, "ol") if ($found_string =~ m/<OL/i);
	$new_text = clean_empty_tag($new_text, "ul") if ($found_string =~ m/<UL/i);

	$new_text = "$titles$new_text";
	substr($newhtml, $found_string_end_pos - length($found_string) + $count, length($data[0])) = "$new_text";
	$count += length($new_text) - length($data[0]);
    }
    print "\t+Fix in html menus in lists.\t". (WikiCommons::get_time_diff) ."\n";
    return $newhtml;
}

sub html_tidy {
    my ($html, $indent, $preserve) = @_;

    my $tidy = HTML::Tidy->new({ indent => "$indent", tidy_mark => 0, doctype => 'omit', quote_marks => 'no',
	input_encoding => "utf8", output_encoding => "raw", clean => 'no', show_body_only => 1,
	preserve_entities => "$preserve"});
    $html = $tidy->clean($html);
    return Encode::encode('utf8', $html);
}

sub cleanup_html {
    my ($html, $file_name) = @_;
    my ($name,$dir,$suffix) = fileparse($file_name, qr/\.[^.]*/);

    print "\t-Fix html file $name.html.\t". (WikiCommons::get_time_diff) ."\n";
    $html =~ s/&nbsp;/ /gs;
    $html = html_clean_tables_in_menu($html);
WikiCommons::write_file("$dir/html_clean_tables_in_menu.$name.html", $html, 1);
    $html = html_clean_menu_in_tables($html);
WikiCommons::write_file("$dir/html_clean_menu_in_tables.$name.html", $html, 1);
    $html = html_clean_menu_in_lists($html);
WikiCommons::write_file("$dir/html_clean_menu_in_lists.$name.html", $html, 1);
    $html = clean_empty_tag($html, 'span');
WikiCommons::write_file("$dir/html_clean_empty_tag_span.$name.html", $html, 1);
    $html = clean_empty_tag($html, 'font');
WikiCommons::write_file("$dir/html_clean_empty_tag_font.$name.html", $html, 1);
    $html =~ s/\n/ /gs;
    $html = html_tidy( $html, 0, 1 );
WikiCommons::write_file("$dir/html_tidy.$name.html", $html, 1);

    my $just_test = html_clean_menu_in_tables($html);
    die "shit menu in ol\n" if($html ne $just_test);
    WikiCommons::write_file("$dir/$name.fixed.html", $html, 1);
    print "\t+Fix html file $name.html.\t". (WikiCommons::get_time_diff) ."\n";

    return $html;
}

sub make_wiki_from_html {
    my $html_file = shift;
    my ($name,$dir,$suffix) = fileparse($html_file, qr/\.[^.]*/);

    open (FILEHANDLE, "$html_file") or die "at wiki from html Can't open file $html_file: ".$!."\n";
    my $html = do { local $/; <FILEHANDLE> };
    close (FILEHANDLE);

    $html = cleanup_html($html, $html_file);

    print "\t-Generating wiki file from $name$suffix.\t". (WikiCommons::get_time_diff) ."\n";
    my $strip_tags = [ '~comment', 'head', 'script', 'style', 'strike'];
    my $wc = new HTML::WikiConverter(
	dialect => 'MediaWiki_Mind',
	strip_tags => $strip_tags,
    );
    my $wiki = $wc->html2wiki($html);
    WikiCommons::write_file("$dir/original.$name.wiki", $wiki, 1);

    if ($debug eq "yes") {
	my $parsed_html = $wc->parsed_html;
	WikiCommons::write_file("$dir/parsed.$name.html", $parsed_html, 1);
    }
    print "\t+Generating wiki file from $name$suffix.\t". (WikiCommons::get_time_diff) ."\n";

    my $image_files = ();
    print "\t-Fixing wiki.\t". (WikiCommons::get_time_diff) ."\n";
    $wiki =~ s/[ ]{8}/\t/gs;
    $wiki = fix_wiki_chars($wiki);
WikiCommons::write_file("$dir/fix_wiki_chars.$name.txt", $wiki, 1);
#     $wiki = fix_wiki_menus( $wiki, $dir );
# WikiCommons::write_file("$dir/fix_wiki_menus.$name.txt", $wiki, 1);
    ($wiki, $image_files) = fix_wiki_tables( $wiki, $dir );
WikiCommons::write_file("$dir/fix_wiki_tables.$name.txt", $wiki, 1);
    ($wiki, $image_files) = fix_wiki_images( $wiki, $image_files, $dir );
WikiCommons::write_file("$dir/fix_wiki_images.$name.txt", $wiki, 1);
    $wiki = fix_wiki_footers( $wiki );
WikiCommons::write_file("$dir/fix_wiki_footers.$name.txt", $wiki, 1);
    $wiki = fix_wiki_links_menus( $wiki );
WikiCommons::write_file("$dir/fix_wiki_links_menus.$name.txt", $wiki, 1);
    $wiki = fix_wiki_url( $wiki );
WikiCommons::write_file("$dir/fix_wiki_url.$name.txt", $wiki, 1);
    $wiki = fix_wiki_link_to_sc( $wiki );
WikiCommons::write_file("$dir/fix_wiki_link_to_sc.$name.txt", $wiki, 1);
    $wiki = fix_external_links( $wiki );
WikiCommons::write_file("$dir/fix_external_links.$name.txt", $wiki, 1);
    $wiki = fix_small_issues( $wiki );
WikiCommons::write_file("$dir/fix_small_issues.$name.txt", $wiki, 1);
    $wiki = fix_tabs( $wiki );
WikiCommons::write_file("$dir/fix_tabs.$name.txt", $wiki, 1);
    ## colapse spaces (here, so we don't mess with the lists)
    $wiki =~ s/ +/ /gm;
    $wiki =~ s/^[\f ]+|[\f ]+$//mg;
    $wiki = wiki_fix_lists( $wiki );
WikiCommons::write_file("$dir/fix_lists.$name.txt", $wiki, 1);
    $wiki = fix_wiki_menus( $wiki, $dir );
WikiCommons::write_file("$dir/fix_wiki_menus.$name.txt", $wiki, 1);

    $wiki =~ s/^[:\s]*$//gm;
    ## remove consecutive blank lines
    $wiki =~ s/(\n){4,}/\n\n/gs;
    ## more new lines for menus and tables
    $wiki =~ s/\n([ \t]*=+[ \t]*)(.*?)([ \t]*=+[ \t]*)\n/\n\n\n$1$2$3\n/gm;
    $wiki =~ s/\|}\s*{\|/\|}\n\n\n{\|/mg;

    ## FAST AND UGLY
    $wiki =~ s/(<span id="Frame[0-9]{1,}" style=")float: left;/$1/mg;
#     $wiki =~ s/<\/span>/<\/span>\n\n/mg;
    WikiCommons::write_file("$dir/$name.wiki", $wiki);
    print "\t+Fixing wiki.\t". (WikiCommons::get_time_diff) ."\n";

    return ($wiki, $image_files);
}

sub fix_tabs {
    my $wiki = shift;
    my $newwiki = $wiki;
    my $count = 0;
    while ($wiki =~ m/^([ \t]+)(.*?)$/gm ) {
	my $found_string = $&;
	my $str = $2;
	my $found_string_end_pos = pos($wiki);
	my $spaces = $1;
	next if ! defined $str;
	$spaces =~ s/\t/:/g;
# 	$spaces =~ s/ //g;
	my $new = "$spaces$str";
	substr($newwiki, $found_string_end_pos - length($found_string) + $count, length($found_string)) = "$new";
	$count += length($new) - length($found_string);
    }
    $wiki = $newwiki;
    return $wiki;
}

sub fix_small_issues {
    my $wiki = shift;

    ## replace breaks
    $wiki =~ s/(<BR>)|(<br\ \/>)/\n\n/gmi;
    ## remove table of content
    $wiki =~ s/\'\'\'Content\'\'\'[\s]*<div id="Table of Contents.*?>.*?<\/div>//gsi;
    $wiki =~ s/(<u>)?(\'\'\'Table of Content[s]?\'\'\')?(<\/u>)?[\s]*<div id="Table of Contents.*?>.*?<\/div>//gsi;
# #     $wiki =~ s/\'\'\'Content\'\'\'[\s]*<div id="Table of Contents.*?>.*?<\/div>//gsi;
    ## remove empty sub
    $wiki =~ s/<sub>[\s]{0,}<\/sub>//gsi;
    ## remove empty div
    $wiki =~ s/<div>[\s]{0,}<\/div>//gsi;
#     $wiki =~ s/<span[^>]*>\s*?<\/span>//gsi;
#     $wiki =~ s/<font[^>]*>\s*?<\/font>//gsi;

    $wiki =~ s/(<center>)|(<\/center>)//gmi;

    $wiki =~ s/\r\n?/\n/gs;
    return $wiki;
}

sub fix_external_links {
    my $wiki = shift;
    $wiki =~ s/([^\[])(\[)(\/%5C%5C)(.*?)(])/$1$2file:\/\/$3$4$5/gs;
    $wiki =~ s/([^\[])(\[)(\/\/)(.*?)(])/$1$2file:\/\/$3$4$5/gs;
    $wiki =~ s/([^\[])(\[)(\.\.)(.*?)(])/$1$2file:\/\/\.\.$3$4$5/gs;
    return $wiki;
}

sub fix_wiki_chars {
    my $wiki = shift;
    ## fix strange characters
    print "\tFix characters in wiki.\t". (WikiCommons::get_time_diff) ."\n";
    ## decode utf8 character in hex: perl -e 'print sprintf("\\x{%x}", $_) foreach (unpack("C*", "�"));print"\n"'
    # copyright
#     $wiki =~ s/\x{c3}\x{93}/\x{C2}\x{A9}/gs;
## old
    ## get ascii hex values from http://www.mikezilla.com/exp0012.html  is ascii %EF%192%17E which is utf \x{e2}\x{87}\x{92}
    # numbers ??
#     $wiki =~ s/\x{B2}/2/gs;
#     $wiki =~ s/\x{B0}/0/gs;
#     $wiki =~ s/\x{B5}/5/gs;
    # copyright
    $wiki =~ s/\x{EF}\x{192}\x{A3}/\x{C2}\x{A9}/gs;
    $wiki =~ s/\x{EF}\x{192}\x{201C}/\x{C2}\x{A9}/gs;
    $wiki =~ s//\x{C2}\x{A9}/gs;
    ## registered
    $wiki =~ s/\x{EF}\x{192}\x{2019}/\x{C2}\x{AE}/gs;
    $wiki =~ s//\x{C2}\x{AE}/gs;
    ## trademark
    $wiki =~ s/\x{EF}\x{192}\x{201D}/\x{E2}\x{84}\x{A2}/gs;
    $wiki =~ s//\x{E2}\x{84}\x{A2}/gs;
    ## long line
    $wiki =~ s/\x{E2}\x{20AC}\x{201D}/\x{E2}\x{80}\x{93}/gs;
    $wiki =~ s/\x{E2}\x{20AC}\x{201C}/\x{E2}\x{80}\x{93}/gs;
    ## puiu
    $wiki =~ s//\x{e2}\x{97}\x{bb}/gs;
    ## RIGHTWARDS arrow
    $wiki =~ s/\x{EF}\x{192}\x{A8}/\x{e2}\x{86}\x{92}/gs;
    $wiki =~ s/\x{E2}\x{2020}\x{2019}/\x{e2}\x{86}\x{92}/gs;
    $wiki =~ s/\x{EF}\x{192}\x{A0}/\x{e2}\x{86}\x{92}/gs;
    $wiki =~ s//\x{e2}\x{86}\x{92}/gs;
    ## LEFTWARDS arrow
    $wiki =~ s/\x{EF}\x{192}\x{178}/\x{e2}\x{86}\x{90}/gs;
    $wiki =~ s//\x{e2}\x{86}\x{90}/gs;
    ## double arrow:
    $wiki =~ s/\x{EF}\x{192}\x{17E}/\x{e2}\x{87}\x{92}/gs;
    ## 3 points
    $wiki =~ s/\x{E2}\x{20AC}\x{A6}/.../gs;
    ## circle
    $wiki =~ s/\x{EF}\x{201A}\x{B7}/\x{e2}\x{97}\x{8f}/gs;
    $wiki =~ s//\x{e2}\x{97}\x{8f}/gs;
    ## black square %EF%201A%A7
    $wiki =~ s//\x{e2}\x{96}\x{a0}/gs;
    ## CHECK MARK
    $wiki =~ s/\x{EF}\x{81}\x{90}/\x{e2}\x{9c}\x{94}/gs;
    $wiki =~ s/\x{EF}\x{192}\x{BC}/\x{e2}\x{9c}\x{94}/gs;
    $wiki =~ s//\x{e2}\x{9c}\x{94}/gs;
    ## BALLOT X
    $wiki =~ s/\x{EF}\x{81}\x{8F}/\x{e2}\x{9c}\x{98}/gs;
    $wiki =~ s/\x{EF}\x{192}\x{BB}/\x{e2}\x{9c}\x{98}/gs;
    $wiki =~ s//\x{e2}\x{9c}\x{98}/gs;
    ## CIRCLE BACKSLASH
    $wiki =~ s/\x{EF}\x{81}\x{2014}/\x{e2}\x{9c}\x{98}/gs;
    $wiki =~ s//\x{e2}\x{83}\x{A0}/gs;

    return $wiki;
}

sub fix_wiki_menus {
    my ($wiki, $dir) = @_;
    print "\t-Fix menus from wiki.\t". (WikiCommons::get_time_diff) ."\n";
    $wiki =~ s/^[ \t]*[#*]+[ \t]*(=+)(.*?)(=+)[ \t]*$/$1$2$3/gm;
    ## remove empty menus (maybe it's cutout)
    $wiki =~ s/^[ \t]*(=+)[ \t]*$//gm;

    ## fix menus
    if ($dir =~ m/\/DB Documentation Mediation -- 5.30 -- 5.30.017 GN -- DB/g) {
	$wiki =~ s/^===Provisioning=$/=Provisioning=/gm;
    }
    print "\tClean up menus.\t". (WikiCommons::get_time_diff) ."\n";
    my $newwiki = $wiki;
    my $count = 0;
    while ($wiki =~ m/\n[ \t]*(=+)[ \t]*(.*?)[ \t]*(=+)[ \t]*\n/g ) {
	my $found_string = $&;
	my $found_string_end_pos = pos($wiki);

	my $start = $1;
	my $menu = $2;
	my $fix_menu = $menu;
	my $end = $3;
	$start =~ s/^\s//g; $start =~ s/\s$//g; $end =~ s/^\s//g; $end =~ s/\s$//g;
	die "menu item $menu does not seem correct: $start$menu$end.\t". (WikiCommons::get_time_diff) ."\n" if ( length($start) != length($end) );

	if ($fix_menu =~ m/(<([^>]*)>)/) {
	    die "shit menu: $menu: $1\n" if ("$1" ne "<nowiki>") && ("$1" ne "<sup>") && ("$1" !~ m/<font[^>]*>/) && ("$1" !~ m/^<span ?/) && ("$1" ne "<u>");
	}
	##remove numbers from beginning
	$fix_menu =~ s/\s*([[:digit:]]{1,2}\.)*([[:digit:]]{1,2})*\s*([^<])/$3/;
	$fix_menu =~ s/^\.//;
	$fix_menu =~ s/(<u>)|(<\/u>)//g;
	$fix_menu =~ s/<font[^>]*>(.*?)<\/font>/$1/gi;
	$fix_menu =~ s/<span[^>]*>(.*?)<\/span>/$1/gi;
	if ($fix_menu =~ m/\[#(.*?)\ (.*?)\]/) {
	    my $q = $2;
	    $fix_menu =~ s/\[#(.*?)\ (.*?)\]/$q/g;
	}
	my $new = "\n$start$fix_menu$end\n";
	substr($newwiki, $found_string_end_pos - length($found_string) + $count, length($found_string)) = "$new";
	$count += length($new) - length($found_string);
    }
    $wiki=$newwiki;
    print "\t+Fix menus from wiki.\t". (WikiCommons::get_time_diff) ."\n";
    return $wiki;
}

sub fix_wiki_tables {
    my ($wiki, $dir) = @_;
    print "\tFix tables from wiki.\t". (WikiCommons::get_time_diff) ."\n";
    my $image_files = ();
    ## fix images from tables:
    my $newwiki = $wiki;
    while ($wiki =~ m/(\{\|.*?\|\})/sg ) {
	my $table=$1;
	my $tmp = "\n".$table;
	$table = quotemeta $table;
	if ($tmp =~ m/(\[\[Image:)([[:print:]].*?)(\]\])/) {
	    my $img_file = uri_unescape( $2 ) ;
	    my $pic_name = $img_file;
	    $pic_name =~ s/(.*?)(\|.*)/$1/;
	    push (@$image_files,  "$dir/$pic_name");
	    next if ($img_file =~ /\|/ );

	    my $info = image_info("$dir/$img_file");
	    if (my $error = $info->{error}) {
		die "Can't parse in table image info ($img_file): $error.\t". (WikiCommons::get_time_diff) ."\n";
	    } else {
		my($w, $h) = dim($info);
		if ( $w > 400 || $h > 400 ) {
		    print "\tFixing size for image $img_file.\n";
		    $tmp =~ s/(\[\[Image:)([[:print:]].*?)(\]\])/$1$2|400px$3/;
		} else {
		    $tmp =~ s/(\[\[Image:)([[:print:]].*?)(\]\])/$1$2|in_table$3/;
		}
	    }
	}
	$newwiki =~ s/$table/$tmp/;
    }
    $wiki = $newwiki;
    return ($wiki, $image_files);
}

sub fix_wiki_images {
    my ($wiki, $image_files, $dir) = @_;
    print "\tFix images from wiki.\t". (WikiCommons::get_time_diff) ."\n";
    ## fix images: center, max size 800px
    my $newwiki = $wiki;
    while ($wiki =~ m/(\[\[Image:)([[:print:]].*?)(\]\])/g ) {
	my $start=$1;
	my $name=$2;
	my $end=$3;
	my $img_file = uri_unescape( $name );
	my $pic_name = $img_file;
	$pic_name =~ s/(.*?)(\|.*)/$1/;
	push (@$image_files,  "$dir/$pic_name");
	$name = quotemeta $name;
	next if ($name =~ /\|/ );

	my $info = image_info("$dir/$img_file");
	if (my $error = $info->{error}) {
	    die "Can't parse image info: $error.\t". (WikiCommons::get_time_diff) ."\n";
	} else {
	    my($w, $h) = dim($info);
	    if ( $w > 800 || $h > 800 ) {
		print "\tFixing size for image $img_file.\n";
		$newwiki  =~ s/(\[\[Image:)($name)(\]\])/\n\n$1$2\|center\|800px$3\n\n/;
	    } else {
		$newwiki  =~ s/(\[\[Image:)($name)(\]\])/\n\n$1$2$3\n\n/;
	    }
	}
    }
    $wiki = $newwiki;
    return ($wiki, $image_files);
}

sub fix_wiki_footers {
    my $wiki = shift;
    print "\tFix footers from wiki.\t". (WikiCommons::get_time_diff) ."\n";
    ## fix footers
    $wiki =~ s/(<div id="sdfootnote.*?">)/----\n$1/gsi;
    my $count = 0;
    my  $newwiki = $wiki;
    while ($wiki =~ m/(\[#sdfootnote)([^ ]*) ([^\]]*)(\])/gsi ) {
	my $found_string = $&;
	my $found_string_end_pos = pos($wiki);
	my $start= $1;
	my $string= $3;
	my $end= $4;
	my $striped_srt =  HTML::TreeBuilder->new_from_content($string)->guts->as_text();
	my $new_string = "\[$start"."_"."$striped_srt\|$striped_srt$end\]";
	substr($newwiki, $found_string_end_pos - length($found_string) + $count, length($found_string)) = $new_string;
	$count += length($new_string) - length($found_string);
    }
    $newwiki =~ s/<div id="(sdfootnote[[:digit:]]{1,})">([\s]{1,})\[\[#([[:print:]].*?)\|([[:print:]].*?)\]\](.*?)<\/div>/<span id="$3">$4: $5<\/span>\n\n/gsi;
    return $newwiki;
}

sub fix_wiki_links_menus {
    my $wiki = shift;
    print "\tFix links to menus from wiki.\t". (WikiCommons::get_time_diff) ."\n";
    ## fix links to menus
    my $newwiki = $wiki;
    my $count = 0;
#     while ($wiki =~ m/[^\[]\[#[_]?(.+?)\ \'*(.+?)\'*\s*?\][^\]]/g) {
    while ($wiki =~ m/[^\[]\[#(.+?) (.+?)\s*?\][^\]]/g) {
	my $found_string = $&;
	my $found_string_end_pos = pos($wiki);
	my $new = "";
	my $q = $2;
	my $q_q = quotemeta $q;
	if ($newwiki =~ m/\n([ \t]*=+[ \t]*)($q_q)([ \t]*=+[ \t]*)\n/i ){
	    my $w = $2;
	    $new = "\[\[#$w\|$w\]\]";
	} else {
	    $new = "$q";
	}
	## must take care of first and last chars: [^\[] and [^\]]
	substr($newwiki, $found_string_end_pos - length($found_string) + 1 + $count, length($found_string) - 2) = "$new";
	$count += length($new) - length($found_string) + 2;
    }
    $wiki=$newwiki;
    return $wiki;
}

sub fix_wiki_url {
    my $wiki = shift;
    ### fix url links
    print "\tFix urls from wiki.\t". (WikiCommons::get_time_diff) ."\n";
    my $newwiki = $wiki;
    while ($wiki =~ m/(http:\/\/.*?)\s+/g) {
	my $q = $1;
	my $normalized_q = WikiCommons::normalize_text( $q );
	my $q_q = quotemeta $q;
	$newwiki =~ s/$q_q/$normalized_q/;
    }
    $wiki=$newwiki;
    return $wiki;
}

sub fix_wiki_link_to_sc {
    my $wiki = shift;
    ## for every B1111 make it a link
    print "\tFix links to SC.\t". (WikiCommons::get_time_diff) ."\n";
    my $newwiki = $wiki;
    my $count = 0;
    while ($wiki =~ m/(\[\[Image:[[:print:]]*?B[[:digit:]]{4,}[[:print:]]*?\]\])|(\bB[[:digit:]]{4,}\b)/g ) {
	my $found_string = $&;
	my $found_string_end_pos = pos($wiki);

	next if ($found_string =~ /^\[\[Image:/);
	print "\tSC link: $found_string\n";
	my $new_string = " [[SC:$found_string|$found_string]] ";
	substr($newwiki, $found_string_end_pos - length($found_string)+$count, length($found_string)) = $new_string;
	$count += length($new_string) - length($found_string);
    }
    $wiki = $newwiki;
    return $wiki;
}

sub wiki_fix_lists {
    my ($wiki, $tag) = @_;
    my $count = 0;
    my $newwiki = $wiki;
    my $extractor_li = gen_extract_tagged("<li>", "<\/li>");
    while ($wiki =~ m/((<ol[^>]*>)|(<ul[^>]*>))/gsi ) {
	my $found_string = $&;
	my $found_string_end_pos = pos($wiki);
	my @type = ();

	pos($wiki) -= length($found_string);
	if ($found_string =~ m/^<ol/ ) {
	    push @type, "<ol[^>]*>";
	    push @type, "<\/ol>";
	} elsif ($found_string =~ m/^<ul/ ) {
	    push @type, "<ul[^>]*>";
	    push @type, "<\/ul>";
	} else {
	    die "WRONG: $found_string\n";
	}
	my @data = extract_tagged( $wiki, $type[0], $type[1]);
# 	pos($wiki) = $found_string_end_pos + length($data[0]);
	my $txt = $data[0];
if (! $txt){
    die "nothing for $type[0]\n";
next;
}
	$txt =~ s/\n+/<br>/mg;
	my @data_li = extract_multiple( $txt, [ $extractor_li]);
	my $new_text = "";
	foreach my $h (@data_li) {
	    if ($h =~ m/^(<li>)(.*?)(<\/li>)$/s) {
		my $q = $2; my $start=$1; my $end=$3;
		if ( ($q !~ m/{\|/m) || ($q !~ m/\|}/m) ) {
		    $q =~ s/<br>/<br>:/gs;
		}
		$new_text .= "$start$q$end";
	    } else {
		$new_text .= $h;
	    }
	}
	$new_text = html_tidy( $new_text, 1, 0 );
	$new_text =~ s/<br>/\n/gs;
	$new_text =~ s/^ +: */:/mg;
	substr($newwiki, $found_string_end_pos - length($found_string) + $count, length($data[0])) = "$new_text";
	$count += length($new_text) - length($data[0]);
    }
    return $newwiki;
}

return 1;
