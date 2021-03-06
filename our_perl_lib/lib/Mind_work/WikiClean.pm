package WikiClean;

use warnings;
use strict;
$| = 1; 
$SIG{__WARN__} = sub { die @_ };

use File::Basename;
use URI::Escape;
use Image::Info qw(image_info dim);
use Mind_work::WikiCommons;
use Data::Dumper;
$Data::Dumper::Sortkeys = 1;
use HTML::TreeBuilder;
use HTML::WikiConverter;
use Log::Log4perl qw(:easy);
use File::Path;
use File::Copy;
use Text::Balanced qw (
    extract_tagged
    extract_multiple
    gen_extract_tagged
    );
use Encode;

our $debug = "no";

# sub tree_remove_strike {
#     my $tree = shift;
#     INFO " Remove strikes.\n";
#     foreach my $a_tag ($tree->guts->look_down(_tag => "strike")) {
# 	$a_tag->detach;
#     }
#     return $tree;
# }

sub tree_clean_empty_p {
    my $tree = shift;
    INFO " Clean empty p.\n";
    foreach my $a_tag ($tree->guts->look_down(_tag => "p")) {
	$a_tag->detach, next if ($a_tag->is_empty);
	my $h = HTML::Element->new('br');
	$a_tag->preinsert($h);
    }
    return $tree;
}

sub tree_is_empty_p {
    my $tag = shift;
    foreach my $a_tag ($tag->content_list) {
	return 0  if (! ref $a_tag || (ref $a_tag && $a_tag->tag ne "br") );
    }
    return 1;
}

sub tree_clean_div {
    my $tree = shift;
    INFO " Clean div.\n";
    foreach my $a_tag ($tree->guts->look_down(_tag => "div")) {
	my $tag_name = $a_tag->tag;
	my $id = 0;
	foreach my $attr_name ($a_tag->all_external_attr_names){
	    my $attr_value = $a_tag->attr($attr_name);
	    if ( ($attr_name eq "type" && $attr_value =~ m/^HEADER$/i)
		    || $attr_name eq "dir"
		    || $attr_name eq "lang"
		    || $attr_name eq "title"
		    || $attr_name eq "align") {
		$a_tag->attr("$attr_name", undef);
	    } elsif (($attr_name eq "type" && $attr_value =~ m/^FOOTER$/i) || $attr_name eq "style"
		|| $attr_name eq "href") {
	    } elsif ($attr_name eq "id" ) {
		$id++;
	    } else {
# 		LOGDIE "Unknown tag in div: $attr_name = $attr_value\n";
# 		return undef;
		INFO "Unknown tag in div: $attr_name = $attr_value\n";
		$a_tag->attr("$attr_name", undef);
	    }
	}
	my $nr_attr = scalar $a_tag->all_external_attr_names();
	$a_tag->replace_with_content() if ( ( $nr_attr == 1 && $id > 0) || $nr_attr == 0 );
    }
    return $tree;
}

sub tree_remove_TOC {
    my $tree = shift;
    INFO "\t-Clean table of contents.\n";
    foreach my $a_tag ($tree->guts->look_down(_tag => "div")) {
	if (defined $a_tag->attr('id') && $a_tag->attr('id') =~ m/^Table of Contents[0-9]$/ ){
	    INFO "\tfound TOC: ".$a_tag->attr('id')."\n" ;
	    $a_tag->detach;
	}
    }
    foreach my $a_tag ($tree->guts->look_down(_tag => "multicol")) {
	if (defined $a_tag->attr('id') && $a_tag->attr('id') =~ m/^Alphabetical Index[0-9]$/ ){
	    INFO "\tfound index: ".$a_tag->attr('id')."\n" ;
	    $a_tag->detach;
	}
    }
    INFO "\t+Clean table of contents.\n";

    return $tree;
}

sub tree_only_one_body {
    my $tree = shift;
    foreach my $a_tag ($tree->guts->look_down(_tag => "body")) {
	my $dad = $a_tag->parent->tag;
	LOGDIE "Body and html tags are strange ".$dad.".\n" if $dad ne "html" || $a_tag->parent->parent;
    }
}

sub heading_new_line {
    my $tree = shift;
    foreach my $a_tag ($tree->descendants()) {
	if ($a_tag->tag =~ m/^h[0-9]{1,2}$/) {
	    $a_tag->postinsert(['br']);
	    $a_tag->preinsert(['br']);
	}
    }
    return $tree;
}

sub tree_fix_links_images {
    my ($tree, $dir) = @_;
    INFO "\t Fix links.\n";
    my $old_files_for_delete;
    foreach (@{  $tree->extract_links()  }) {
	my($link, $element, $attr, $tag) = @$_;
	if ($tag eq "img" || $tag eq "body") {
	    my $name_img = uri_unescape($link);
	    $name_img =~ s/^\.\.\///;
	    if (! -f "$dir/$name_img") {
		INFO "Can't find file $dir/$name_img.\n";
		next;
	    }
	    $old_files_for_delete->{"$dir/$name_img"} = 1;
	    my $name_new = "$name_img.conv.jpg";
	    system("convert", "$dir/$name_img", "-background", "white", "-flatten", "$dir/$name_new") == 0 or LOGDIE "error runnig convert: $!.\n";
	    ## importImages.php Segmentation fault
	    system("mogrify", "-strip", "$dir/$name_new") == 0 or LOGDIE "error runnig mogrify: $!.\n"; 
	    ## get correct hash after convert/mogrify
	    my $name_new_final = WikiCommons::get_file_md5("$dir/$name_new")."_conv.jpg";
	    move("$dir/$name_new", "$dir/$name_new_final") or die "Copy failed: $!";
	    $element->attr($attr, uri_escape($name_new_final));
	}
    }
    unlink $_  foreach (keys %$old_files_for_delete);
    return $tree;
}

sub cleanup_html {
    my ($html, $file_name) = @_;
    my ($name,$dir,$suffix) = fileparse($file_name, qr/\.[^.]*/);

    INFO "\t-Fix html file $name.html.\n";

    my $tree = HTML::TreeBuilder->new();

    $tree->no_space_compacting(1);
    $tree = $tree->parse_content(decode_utf8($html));
    tree_only_one_body($tree);

    my $i = 0;
WikiCommons::write_file("$dir/".++$i.". original.$name.html", tree_to_html($tree), 1) if $debug eq "yes";
    $tree = tree_remove_TOC($tree);
WikiCommons::write_file("$dir/".++$i.". tree_remove_TOC.$name.html", tree_to_html($tree), 1) if $debug eq "yes";
    $tree = heading_new_line($tree);

#     $tree->no_space_compacting(1);
#     my $text1 = tree_to_text($tree);
# WikiCommons::write_file("$dir/".++$i.". tree_text1.$name.txt", $text1, 1) if $debug eq "yes";
#     $tree->no_space_compacting(0);
    $tree = tree_fix_links_images($tree, $dir);
    ## after TOC, because in TOC we use div
    $tree = tree_clean_empty_p($tree);
WikiCommons::write_file("$dir/".++$i.". tree_clean_empty_p.$name.html", tree_to_html($tree), 1) if $debug eq "yes";
    $tree = tree_clean_div($tree) || return undef;
WikiCommons::write_file("$dir/".++$i.". tree_clean_div.$name.html", tree_to_html($tree), 1) if $debug eq "yes";

    $tree = tree_clean_font($tree);
WikiCommons::write_file("$dir/".++$i.". tree_clean_font.$name.html", tree_to_html($tree), 1) if $debug eq "yes";
    $tree = tree_clean_span($tree);
WikiCommons::write_file("$dir/".++$i.". tree_clean_span.$name.html", tree_to_html($tree), 1) if $debug eq "yes";
    $tree = tree_clean_bold($tree);

    $tree = tree_clean_tables($tree) || return undef;
WikiCommons::write_file("$dir/".++$i.". tree_clean_tables.$name.html", tree_to_html($tree), 1) if $debug eq "yes";

    $tree = tree_clean_headings($tree) || return undef;
WikiCommons::write_file("$dir/".++$i.". tree_clean_headings.$name.html", tree_to_html($tree), 1) if $debug eq "yes";

    $tree = tree_clean_lists($tree);
WikiCommons::write_file("$dir/".++$i.". tree_clean_lists.$name.html", tree_to_html($tree), 1) if $debug eq "yes";
    $tree = tree_clean_lists_ol_ul($tree);
    $tree = tree_clean_span_to_div($tree);
WikiCommons::write_file("$dir/".++$i.". tree_clean_span_to_div.$name.html", tree_to_html($tree), 1) if $debug eq "yes";

    $tree = tree_bgcolor_from_tables($tree);
## can't do it
#     $html = html_fix_html_tabs($html);
# WikiCommons::write_file("$dir/html_fix_html_tabs.$name.html", $html, 1);
    ## do i need this?:
#     ### keep some spaces from dissapearing
#     $html =~ s/\n/ /gs;
#     $html = html_tidy( $html, 0 );
# WikiCommons::write_file("$dir/html_tidy2.$name.html", $html, 1);

#     my $text2 = tree_to_text($tree);
# WikiCommons::write_file("$dir/".++$i." html_text2.$name.txt", $text2, 1) if $debug eq "yes";
#     my $clean_text1 = $text1;
#     my $clean_text2 = $text2;
#     $clean_text1 =~ s/\s*//gs;
#     $clean_text2 =~ s/\s*//gs;
#     $clean_text1 =~ s/\x{c2}\x{a0}//gs;
#     $clean_text2 =~ s/\x{c2}\x{a0}//gs;
#     if ($clean_text1 ne $clean_text2) {{
# 	last if $name eq "SC:B04021 STP document" || $name eq "Cashier -- 5.31" ||
# 	    $name eq "Cashier -- 5.30.017 GN" || $name eq "Cashier -- 5.31.006 GN" ||
# 	    $name eq "Cashier -- 5.40" || $name eq "Cashier -- 6.01" ||
# 	    $name eq "CMS:PhonEX ONE Installation Technical Guide 2.2" ||
# 	    $name eq "CMS:PhonEX Pro 8.00 User Manual" ||
# 	    $name eq "RN:6.01.100 MoldTel SP15.012 - Changes -- Release Notes -- MoldTel Release Notes" ||
# 	    $name eq "RN:RN220010 -- CMS";
# WikiCommons::write_file("$dir/".++$i." html_text1.$name.txt", $text1, 1);
# WikiCommons::write_file("$dir/".++$i." html_text2.$name.txt", $text2, 1);
# 	INFO "Missing text after working on html file $name, in dir $dir.\n";
# 	return undef;
#     }}
    ## here we remove/add text, so we use it last
    foreach my $a_tag ($tree->guts->look_down(_tag => "li")) {
	$a_tag->postinsert(['br']);
	$a_tag->preinsert(['br']);
    }

    $tree = tree_fix_numbers_in_headings($tree);
WikiCommons::write_file("$dir/".++$i.". tree_fix_numbers_in_headings.$name.html", tree_to_html($tree), 1) if $debug eq "yes";

    $tree->no_space_compacting(0);
    my $html_res = tree_to_html($tree);
    INFO "\t+Fix html file $name.html.\n";
    $tree = $tree->delete;
WikiCommons::write_file("$dir/$name.fixed.html", $html_res, 1) if $debug eq "yes";
    return Encode::encode('utf8', $html_res);
}

sub tree_fix_numbers_in_headings {
    my $tree = shift;
    INFO " Remove numbers in headings.\n";
    foreach my $a_tag ($tree->descendants()) {
	if ($a_tag->tag =~ m/^h[0-9]{1,2}$/){
	    foreach my $b_tag ($a_tag->content_refs_list){
		if (! ref $$b_tag ){
		    $$b_tag =~ s/^\s*([0-9]{1,}\.)+\s*//;
		    $$b_tag =~ s/^\s*[0-9]{1,}([a-z])\s*/$1/i;
		    $$b_tag =~ s/^\s*([0-9]{1,}\.)+[0-9]{1,}\s*//;
		    $$b_tag =~ s/^\s*[0-9]{1}\s+//;
		    last;
		}
	    }
	}
    }
    return $tree;
}

sub tree_to_text {
    my $tree = shift;
    my $text = $tree->guts ? $tree->guts->as_text() : "";
    return Encode::encode('utf8', $text);
}

sub tree_to_html {
    my $tree = shift;
    my $text = $tree->guts ? $tree->guts->as_HTML(undef, "\t") : "";
    return encode('utf8',$text);
}

sub tree_bgcolor_from_tables {
    my ($tree) = @_;
    INFO " Clean bgcolor.\n";
    ## libreoffice exports tables with an ugly backkground color: #FF0000. we hate this
    foreach my $a_tag ($tree->guts->look_down(_tag => "td")) {
	foreach my $attr_name ($a_tag->all_external_attr_names){
	    my $attr_value = $a_tag->attr($attr_name);
	    next if ( $attr_name ne "bgcolor" || $attr_value ne "#FF0000");
	    INFO "Removing background color $attr_value.\n";
	    $a_tag->attr("bgcolor", undef);
	}
    }
    return $tree;
}

sub tree_clean_font {
    my ($tree) = @_;
    INFO " Clean font.\n";
    foreach my $a_tag ($tree->guts->look_down(_tag => "font")) {
	$a_tag->detach, next if $a_tag->is_empty();
	foreach my $attr_name ($a_tag->all_external_attr_names){
	    my $attr_value = $a_tag->attr($attr_name);
	    next if ( $attr_name eq "color" );
	    if ( $attr_name eq "face" ||$attr_name eq "size"
		    || ($attr_name eq "style" && $attr_value =~ m/^font-size: [0-9]{1,}pt$/i) ){
		$a_tag->attr($attr_name, undef);
		next;
	    }
	    LOGDIE "Attr name for font: $attr_name = $attr_value.\n";
	}
	tree_remove_empty_element($a_tag);
    }
    return $tree;
}

sub tree_clean_bold {
    my $tree = shift;
    INFO " Fix bold tags\n";
    foreach my $a_tag ($tree->guts->look_down(_tag => "b")) {
	TRACE "Found bold tag.\n".Dumper($a_tag->as_text);
	foreach my $attr_name ($a_tag->all_external_attr_names){
	    INFO "\tremove element $attr_name from bold\n";
	    $a_tag->attr($attr_name, undef);
	}
	tree_remove_empty_element($a_tag);
    }
    return $tree;
}

sub tree_remove_empty_element {
    my $a_tag = shift;
    TRACE " Try to remove empty tags ".$a_tag->tag.".\n";
    my $has_content = 0;
    foreach my $b_tag ($a_tag->content_list()){
	if (ref $b_tag){
	    $has_content++;
	    last;
	}
    }

    if ( $a_tag->as_text =~ m/^\s*$/ && ! $has_content ) {
	DEBUG "\tFound empty tag ".$a_tag->tag.".\n".Dumper($a_tag->as_text);
	$a_tag->replace_with_content;
    }
}

sub tree_clean_span_to_div {
    my ($tree, $tag) = @_;
    INFO " Clean span/div.\n";
    ## multiline span
    foreach my $a_tag ($tree->guts->look_down(_tag => "span")) {
	my $multi = 0;
	my $txt = "";
	$multi++ if scalar $a_tag->look_down(_tag => "br");
# 	foreach my $content ($a_tag->content_list()) {
# 	    next if (ref $content);
# 	    $multi++ if $content =~ m/\n{2,}/s;
# 	    $txt .= $content;
# 	}
 $a_tag->tag("mind_tag") if $multi;
# INFO $a_tag->as_text."\n" if $multi;
    }
    return $tree;
}

sub tree_clean_span {
    my ($tree, $tag) = @_;
    INFO " Clean span.\n";
    foreach my $a_tag ($tree->guts->look_down(_tag => "span")) {
	my $delete_span = 0;
# 	$a_tag->detach, next if $a_tag->is_empty();
	my $imgs = "";
	foreach my $attr_name ($a_tag->all_external_attr_names){
	    my $attr_value = $a_tag->attr($attr_name);
	    if ( $attr_name eq "style") {
		my @attr = split ';', $attr_value;
		my $res = undef;
		foreach my $att (@attr) {
		    if ($att =~ m/^\s*background: (#[0-9a-fA-F]{6}|transparent)\s*$/i
			|| $att =~ m/^\s*(font-(weight|style): (normal|italic))\s*$/i
			|| $att =~ m/^\s*(width|height): [0-9.]{1,}(px|in)\s*$/i ) {
			$res .= $att.";";
			$imgs = $1 if ($att =~ m/^\s*width: ([0-9.]{1,}(px|in))\s*$/i);
		    } elsif ($att =~ m/^\s*background: #[0-9a-fA-F]{6} url(.*)\((.*)\)(.*)/i) {
			my $img = $2;
			my $p = HTML::Element->new('p');
			my $imge = HTML::Element->new('img');
			$imgs = $1*100 if ($imgs ne "" && $imgs =~ m/\s*(.*)in\s*$/);
# 			$imgs = 500 if $imgs>500;
			$imge->attr("width", "$imgs") if $imgs ne "";
			$imge->attr("src", "$img");
			$p->push_content($imge);
			$a_tag->postinsert($p);
		    } else {
			if ($att =~ m/^\s*float: (top|left|right)\s*$/i
				    || $att =~ m/^\s*text-decoration:/i
				    || $att =~ m/^\s*letter-spacing:/i
				    || $att =~ m/^\s*color:#[0-9a-f]{6}/i
				    || $att =~ m/^\s*position: absolute\s*$/i
				    || $att =~ m/^\s*(margin-)?(top|left|right): -?[0-9]{1,}(\.[0-9]{1,})?in\s*$/i
				    || $att =~ m/^\s*margin: [0-9]{1,}(\.[0-9]{1,})?in\s*$/i
				    || $att =~ m/^\s*(border|padding)/i) {
			    next;
			} elsif ($att =~ m/^\s*font-variant: (small-caps|normal)\s*$/i
				    || $att =~ m/^\s*text-transform: uppercase\s*$/i) {
			    $res .= $att.";";
			} elsif ($att =~ m/^\s*display: none\s*$/i) {
			    $delete_span = 1;
			} else {
			    LOGDIE "Attr name for span_style = $att.\n";
			}
		    }
		}
		$a_tag->attr("$attr_name", $res);
	    } elsif ( $attr_name eq "id"
		|| $attr_name eq "style" ) {
	    } elsif ( $attr_name eq "class"
		    || $attr_name eq "dir" || $attr_name eq "lang") {
		$a_tag->attr("$attr_name", undef);
	    } else {
		LOGDIE "Attr name for span: $attr_name = $attr_value.\n";
	    }
	}
	if ($delete_span) {
	    $a_tag->detach;
	} else {
	    tree_remove_empty_element($a_tag);
	}
    }
    return $tree;
}

sub tree_clean_headings {
    my $tree = shift;
    INFO "\t-Fix headings.\n";

    foreach my $a_tag ($tree->descendants()) {
	if ($a_tag->tag =~ m/^h[0-9]{1,2}$/) {
	    if (scalar ($a_tag->look_down(_tag => "ul"))) {
		$a_tag->replace_with_content;
		next;
	    }

	    my $dad = $a_tag->parent;
	    my $grandpa = $dad->parent;
	    my $grandgrandpa = $grandpa->parent;

	    tree_headings_clean_content($a_tag);
	    tree_headings_clean_content($a_tag); ## leftovers from like span
	    tree_headings_clean_images($a_tag);
	    ### remove empty headings
	    my $heading_txt = $a_tag->as_text();
	    $heading_txt =~ s/\s+/ /gm;
	    if ( $heading_txt =~ m/^\s*$/) {
		$a_tag->detach;
		next;
	    }

##if we have a heading in a list and it's lists all the way down, extract content
## else, make it bold and leave
	    if ( ($dad->tag eq "body" && $grandpa->tag eq "html" && not($grandgrandpa)) ||
		    (($dad->tag eq "div" | $dad->tag eq "a") && $grandpa->tag eq "body" && $grandgrandpa->tag eq "html") ) {
		## we're cool
	    } elsif ($dad->tag =~ m/(li|ol|ul|td|tr)/) {
		tree_headings_in_lists($a_tag);
	    }

	    tree_headings_clean_attr($a_tag);
	}
    }

    INFO "\t+Fix headings.\n";
    return $tree;
}

sub tree_headings_clean_images {
    my $a_tag = shift;
    TRACE " Clean images in heading.\n";
    $a_tag->preinsert(['br']);
    foreach my $b_tag ($a_tag->content_refs_list){
	next if ! ref $$b_tag;
	my $tag = $$b_tag->tag();
	if ($tag eq "img" || $tag eq "table") {
	    my $img = $$b_tag->clone;
# INFO $img->as_HTML."\n";
	    $$b_tag->detach;
	    my $p = HTML::Element->new('p');
	    my $b = HTML::Element->new('br');
# 	    my $img = HTML::Element->new($img);
	    $b->push_content($p);
	    $b->push_content($img);
	    $a_tag->postinsert($b);
	}
    }
}

sub tree_headings_clean_content {
    my $a_tag = shift;
    TRACE " Clean content in headings.\n";
## extract images from heading and put it before it. Remove other attr
    foreach my $b_tag ($a_tag->content_refs_list){
	next if ! ref $$b_tag;
	my $tag = $$b_tag->tag();
	if ($tag eq "img" || $tag eq "table" || $tag eq "strike" ) {
	    ## later alligator
	} elsif ($tag eq "br" || $tag eq "a") {
	    $$b_tag->detach;
	} elsif ($tag eq "sup") {
	} elsif ( $tag eq "span" || $tag eq "font" || $tag eq "u" || $tag eq "b" || $tag eq "em"
	    || $tag eq "center" || $tag eq "i" || $tag eq "strong") {
	    $$b_tag->replace_with_content;
	} else {
	    LOGDIE "reference in heading: $tag\n";
	    return undef;
	}
    }

    foreach my $b_tag ($a_tag->content_refs_list){
	next if ref $$b_tag;
	$$b_tag =~ s/\s+/ /gm;
    }
}

sub tree_headings_clean_attr {
    my $a_tag = shift;
    DEBUG " Clean up heading attributes.\n";
    foreach my $attr_name ($a_tag->all_external_attr_names){
	my $attr_value = $a_tag->attr($attr_name);
	if ( $attr_name eq "style"
		|| $attr_name eq "class"
		|| $attr_name eq "align"
		|| $attr_name eq "lang"
		|| $attr_name eq "dir") {
	    $a_tag->attr("$attr_name", undef);
# 		} elsif ($attr_name eq "cellpadding") {
	} else {
	    LOGDIE "Unknown attr in heading: $attr_name = $attr_value.\n";
	    return undef;
	}
    }
}

sub tree_headings_in_lists {
    my $a_tag = shift;
    INFO " Found a heading inside a list. Cleaning...\n";
    $a_tag->attr( 'class', undef );
    $a_tag->attr( 'style', undef );
    my @ancestors = ();
my @q=();
    foreach my $parent ($a_tag->lineage()){
	if ( $parent->tag =~ m/^(ul|ol|li|body|html|div|a)$/){
	    push @ancestors, $parent
	} else {
@q=@ancestors if $parent->tag =~ m/^(tr|td|table)$/;
	    @ancestors = ();
	    last
	}
    }

    if ( scalar @ancestors ) {
# 	INFO "all lists here: ".Encode::encode('utf8', $a_tag->as_text)."\n\t";
	foreach my $parent (@ancestors) {
# 	    INFO "".$parent->tag."\t";
	    last if $parent->tag eq "body";
	    $parent->replace_with_content;
	}
# 	INFO "\n";
    } else {
	LOGDIE "not all lists here: ".Encode::encode('utf8', $a_tag->as_text)."\n".Dumper(@q) if ! scalar @q;
	INFO "Replace ".$a_tag->tag."with bold.\n";
	$a_tag->tag("b");
    }
}

sub tree_clean_tables_attributes {
    my $a_tag = shift;
    TRACE " Clean table attributes.\n";
    foreach my $attr_name ($a_tag->all_external_attr_names){
	my $attr_value = $a_tag->attr($attr_name);
	if ( $attr_name eq "border"
		|| $attr_name eq "bordercolor"
		|| $attr_name eq "cellspacing"
		|| $attr_name eq "frame"
		|| $attr_name eq "rules"
		|| $attr_name eq "width"
		|| $attr_name eq "dir"
		|| $attr_name eq "bgcolor"
		|| $attr_name eq "align"
		|| $attr_name eq "style"
		|| $attr_name eq "cols"
		|| $attr_name eq "class"
# 			&& ( $attr_value =~ "page-break-(before|after|inside)")
		|| $attr_name eq "hspace"
		|| $attr_name eq "vspace"){
	    $a_tag->attr("$attr_name", undef);
	} elsif ($attr_name eq "cellpadding") {
	} else {
	    LOGDIE "Unknown attr in table: $attr_name = $attr_value.\n";
	    return undef;
	}
    }
}

sub tree_clean_tables {
    my $tree = shift;
    INFO " Clean tables.\n";
    foreach my $a_tag ($tree->guts->look_down(_tag => "table")) {
	### replace all headings with bold
	foreach my $b_tag ($a_tag->descendants()) {
	    if ($b_tag->tag =~ m/^h[0-9]{1,2}$/) {
		$b_tag->tag('b');
		$b_tag->attr( 'class', undef );
		$b_tag->attr( 'style', undef );
	    }
	}
	$a_tag->postinsert(['br']);
	$a_tag->preinsert(['br']);
	tree_clean_tables_attributes($a_tag);
	### replace thead and tbody with content
	foreach my $b_tag ($a_tag->content_list){
	    if (ref $b_tag){
		my $tag = $b_tag->tag;
		if ( $tag eq "thead" || $tag eq "tbody"){
		    $b_tag->replace_with_content;
		}
	    }
	}

	### expect only col and tr
	foreach my $b_tag ($a_tag->content_list){
	    LOGDIE "not reference in table\n" if ! ref $b_tag;
	    my $tag = $b_tag->tag;
	    if ( $tag eq "col" || $tag eq "colgroup"){
		$b_tag->detach;
	    } elsif ( $tag eq "tr" ){
		### clean tr attributes
		foreach my $attr_name ($b_tag->all_external_attr_names){
		    my $attr_value = $b_tag->attr($attr_name);
		    if ( $attr_name eq "valign" || $attr_name eq "class"){
			$a_tag->attr("$attr_name", undef);
		    } elsif ( $attr_name eq "bgcolor") {
		    } else {
			LOGDIE "Unknown attr in tr: $attr_name = $attr_value.\n";
			return undef;
		    }
		}
		### expect only td in tr
		my $has_content = 0;
		foreach my $c_tag ($b_tag->content_list){
		    LOGDIE "not reference in tr\n" if ! ref $c_tag;
		    my $tag = $c_tag->tag;
		    LOGDIE "Unknown tag: $tag\n" if $tag ne "td" && $tag ne "th";
		    ### clean td attributes
		    foreach my $attr_name ($c_tag->all_external_attr_names){
			my $attr_value = $c_tag->attr($attr_name);
			if ( $attr_name eq "width"
				|| $attr_name eq "height"
				|| $attr_name eq "align"
				|| $attr_name eq "style"
				|| $attr_name eq "sdnum"
				|| $attr_name eq "sdval"
				|| $attr_name eq "valign"){
			    $c_tag->attr("$attr_name", undef);
			} elsif ($attr_name eq "bgcolor" || $attr_name eq "colspan" || $attr_name eq "rowspan") {
			} else {
			    LOGDIE "Unknown attr in $tag: $attr_name = $attr_value.\n";
			}
		    }
		    ### remove empty td, add new lines
		    foreach my $d_tag ($c_tag->content_refs_list){
			if ( ref $$d_tag && ( $$d_tag->tag eq "p" || $$d_tag->tag eq "br") ) {
			    $$d_tag->postinsert(['br']) if $$d_tag->tag ne "br";
			    $has_content++ if $$d_tag->tag eq "p" && ! tree_is_empty_p($$d_tag);
			} elsif ( ref $$d_tag ) {
			    $has_content++;
			} else {
			    $$d_tag =~ s/$/\n/gm;
			}
		    }
		    next if $has_content;
		    my $txt = $c_tag->as_text();
		    $txt =~ s/\s*//gs;
		    $has_content++ if ( $txt ne '');
		}
		$b_tag->detach if ( ! $has_content );
	    } else {
		LOGDIE "Unknown tag in table: $tag.\n";
		return undef;
	    }
	}
    }
    return $tree;
}

sub tree_clean_lists_ol_ul {
    my $tree = shift;
    INFO " Clean lists ol ul.\n";
    foreach my $a_tag ($tree->guts->look_down(_tag => "ol")) {
	foreach my $attr_name ($a_tag->all_external_attr_names){
	    my $attr_value = $a_tag->attr($attr_name);
	    if (($attr_name eq "style" && $attr_value =~ m/^\s*(margin-)?(top|left|right): -?[0-9]{1,}(\.[0-9]{1,})?in\s*$/i)){
		$a_tag->attr("$attr_name", undef);
	    } elsif (($attr_name eq "start" && $attr_value =~ m/^[0-9]+$/i) ||
		    (($attr_name eq "type" && $attr_value =~ m/^[Ia]$/i))) {
	    } else {
LOGDIE "Unknown attributes for ol/ul:\n".Dumper($attr_name,$attr_value);
	    }
	}
    }
    return $tree;
}

sub tree_clean_lists {
    my $tree = shift;
    INFO " Clean lists.\n";
    ### remove empty lists from body (don't, because we remove numbering lists)
#     foreach my $a_tag ($tree->guts->look_down(_tag => "li")) {
# 	$a_tag->detach() if ! scalar $a_tag->content_list();
#     }
    foreach my $a_tag ($tree->guts->look_down(_tag => "li")) {
	next if ! $a_tag->is_empty();
	my $has_content = 0;
	my $last = "";
	### remove all lists that have no data
	foreach my $parent ($a_tag->lineage()){
	    if ( ($parent->tag !~ m/^(ul|ol|body|html)$/) ||
		    ($parent->tag =~ m/^(ul|ol)$/ && scalar $parent->content_list() > 1)) {
		$has_content++;
		last;
	    }
	    $last = $parent if $parent->tag !~ m/^(body|html)$/;
	}
	if (! $has_content) {
	    if ($a_tag->is_empty()){
		$a_tag->detach();
	    } else {
		$last->detach();
	    }
	}
	foreach my $b_tag ($a_tag->content_refs_list()){
	    next if ref $$b_tag;
	    $$b_tag =~ s/\n/\n<br>/mg;
	}
    }
    return $tree;
}

sub html_tidy {
    my ($html, $indent) = @_;

    my $tidy = HTML::Tidy->new({ indent => "$indent", tidy_mark => 0, doctype => 'omit',
	input_encoding => "utf8", output_encoding => "utf8", clean => 'no', show_body_only => 1,
	preserve_entities => 0});
# ,	preserve_entities => 0,quote_marks => 'no',, literal_attributes => 1
    $html = $tidy->clean($html);
    return Encode::encode('utf8', $html);
    return $html;
}

sub make_wiki_from_html {
    my ($html_file, $type) = @_;
    my ($name,$dir,$suffix) = fileparse($html_file, qr/\.[^.]*/);

    open (FILEHANDLE, "$html_file") or LOGDIE "at wiki from html Can't open file $html_file: ".$!."\n";
    my $html = do { local $/; <FILEHANDLE> };
    close (FILEHANDLE);

    $html = cleanup_html($html, $html_file) || return undef;

    INFO "\t-Generating wiki file from $name$suffix.\n";
    my $wiki;
    my $strip_tags = [ '~comment', 'head', 'script', 'style'];
    push @$strip_tags, 'strike' if defined $type && $type !~ m/mindserve/i;
    my $wc = new HTML::WikiConverter(
	dialect => 'MediaWiki_Mind',
	strip_tags => $strip_tags,
	preserve_bold => 1,
	preserve_italic => 1,
    );
    eval {
    local $SIG{ALRM} = sub { die "alarm\n" };
    alarm 1800;
    $wiki = $wc->html2wiki($html);
WikiCommons::write_file("$dir/original.$name.wiki", $wiki, 1) if $debug eq "yes";
    alarm 0;
    };
    return if $@;

    my $parsed_html = $wc->parsed_html;
WikiCommons::write_file("$dir/parsed.$name.html", $parsed_html, 1) if $debug eq "yes";

    INFO "\t+Generating wiki file from $name$suffix.\n";
    $wiki =~ s/mind_tag/div/gm;

    my $image_files = ();
    INFO "\t-Fixing wiki.\n";
#     $wiki =~ s/[ ]{8}/\t/gs;
    $wiki = fix_wiki_chars($wiki);
WikiCommons::write_file("$dir/fix_wiki_chars.$name.txt", $wiki, 1) if $debug eq "yes";
# exit 1;
    $image_files = get_wiki_images( $wiki, $image_files, $dir );
WikiCommons::write_file("$dir/get_wiki_images.$name.txt", $wiki, 1) if $debug eq "yes";
    $wiki = fix_wiki_footers( $wiki );
WikiCommons::write_file("$dir/fix_wiki_footers.$name.txt", $wiki, 1) if $debug eq "yes";
    $wiki = fix_wiki_links_menus( $wiki );
WikiCommons::write_file("$dir/fix_wiki_links_menus.$name.txt", $wiki, 1) if $debug eq "yes";
    $wiki = fix_wiki_url( $wiki );
WikiCommons::write_file("$dir/fix_wiki_url.$name.txt", $wiki, 1) if $debug eq "yes";
    $wiki = fix_wiki_link_to_sc( $wiki );
WikiCommons::write_file("$dir/fix_wiki_link_to_sc.$name.txt", $wiki, 1) if $debug eq "yes";
    $wiki = fix_external_links( $wiki );
WikiCommons::write_file("$dir/fix_external_links.$name.txt", $wiki, 1) if $debug eq "yes";
#     $wiki = fix_tabs( $wiki );
# WikiCommons::write_file("$dir/fix_tabs.$name.txt", $wiki, 1);
#     $wiki = wiki_fix_lists( $wiki );
# WikiCommons::write_file("$dir/fix_lists.$name.txt", $wiki, 1);
#     $wiki = fix_wiki_menus( $wiki, $dir );
# WikiCommons::write_file("$dir/fix_wiki_menus.$name.txt", $wiki, 1);
    $wiki = fix_small_issues( $wiki );
    $wiki =~ s/^[:\s]*$//gm; ## not good for crm
WikiCommons::write_file("$dir/fix_small_issues.$name.txt", $wiki, 1) if $debug eq "yes";

    WikiCommons::write_file("$dir/$name.wiki", $wiki);
    INFO "\t+Fixing wiki.\n";

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

    INFO "Fix small wiki issues.\n";
    ## replace breaks
    $wiki =~ s/(<BR>)|(<br\ \/>)/\n\n/gmi;
    ## fix start with shit from wiki
    $wiki =~ s/^(\*|#|;|:|=|!|----)/<nowiki>$1<\/nowiki>/gm;
    ## remove empty sub
    $wiki =~ s/<sub>[\s]{0,}<\/sub>//gsi;
    $wiki =~ s/(<center>)|(<\/center>)/\n\n/gmi;
    ## remove empty tables
    $wiki =~ s/\n\{\|.*\n+\|\}\n//gm;;
    $wiki =~ s/\r\n?/\n/gs;
    ## remove empty headings
    $wiki =~ s/\n=+\n/\n/gm;;
    ## remove consecutive blank lines
    $wiki =~ s/(\n){4,}/\n\n\n/gs;
    $wiki =~ s/^[ \t]+//mg;
    ## collapse spaces
    $wiki =~ s/[ \t]{2,}/ /mg;
    ## remove  unnecessary new lines
    $wiki =~s/([a-z])\n([a-z])/$1 $2/mgi;
    ## more new lines for menus and tables
    $wiki =~ s/^([ \t]*=+[ \t]*)(.*?)([ \t]*=+[ \t]*)$/\n\n$1$2$3\n/gm;
    $wiki =~ s/^\{\|(.*)$/\n\{\|$1 class="wikitable" /mg;
    $wiki =~ s/\|}\s*{\|/\|}\n\n\n{\|/mg;

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
## old
# #     get ascii hex values from http://www.mikezilla.com/exp0012.html ïƒž is ascii %EF%192%17E which is utf \x{e2}\x{87}\x{92}
# #
# #     get utf8 codes from http://www.fileformat.info/info/unicode/char/25cb/index.htm
# #     decode character in hex (replace character with utf8represantation):
# # 		perl -e 'INFO sprintf("\\x{%x}", $_) foreach (unpack("C*", "�"));print"\n"'
    # copyright
    $wiki =~ s/\x{EF}\x{192}\x{A3}/\x{C2}\x{A9}/gsi;
    $wiki =~ s/\x{EF}\x{192}\x{201C}/\x{C2}\x{A9}/gsi;
    $wiki =~ s/\x{EF}\x{81}\x{97}/\x{e2}\x{a6}\x{b8}/gsi;
    $wiki =~ s/\x{C3}\x{AF}\x{C6}\x{92}\x{E2}\x{80}\x{9C}/\x{C2}\x{A9}/gsi;
    $wiki =~ s/\x{c3}\x{af}\x{c6}\x{92}\x{c2}\x{a3}/\x{C2}\x{A9}/gsi;
    $wiki =~ s/\x{ef}\x{83}\x{93}/\x{C2}\x{A9}/gsi;
    $wiki =~ s/\x{ef}\x{83}\x{a3}/\x{C2}\x{A9}/gsi;
    ## registered
    $wiki =~ s/\x{EF}\x{192}\x{2019}/\x{C2}\x{AE}/gsi;
    $wiki =~ s/\x{c3}\x{af}\x{c6}\x{92}\x{e2}\x{80}\x{99}/\x{C2}\x{AE}/gsi;
    $wiki =~ s/\x{ef}\x{83}\x{92}/\x{C2}\x{AE}/gsi;
    ## trademark
    $wiki =~ s/\x{EF}\x{192}\x{201D}/\x{E2}\x{84}\x{A2}/gsi;
    $wiki =~ s/\x{c3}\x{af}\x{c6}\x{92}\x{e2}\x{80}\x{9d}/\x{E2}\x{84}\x{A2}/gsi;
    $wiki =~ s/\x{ef}\x{83}\x{94}/\x{E2}\x{84}\x{A2}/gsi;

    ## long line
    $wiki =~ s/\x{E2}\x{20AC}\x{201D}/\x{E2}\x{80}\x{93}/gsi;
    $wiki =~ s/\x{E2}\x{20AC}\x{201C}/\x{E2}\x{80}\x{93}/gsi;
    ## puiu / amanda
    $wiki =~ s/\x{c3}\x{af}\x{c6}\x{92}\x{c2}\x{bf}/\x{e2}\x{97}\x{bb}/gsi;
    $wiki =~ s/\x{ef}\x{83}\x{bf}/\x{e2}\x{97}\x{bb}/gsi;
    ## RIGHTWARDS arrow
    $wiki =~ s/\x{EF}\x{192}\x{A8}/\x{e2}\x{86}\x{92}/gsi;
    $wiki =~ s/\x{E2}\x{2020}\x{2019}/\x{e2}\x{86}\x{92}/gsi;
    $wiki =~ s/\x{EF}\x{192}\x{A0}/\x{e2}\x{86}\x{92}/gsi;
    $wiki =~ s/\x{c3}\x{af}\x{c6}\x{92}\x{c2}\x{a8}/\x{e2}\x{86}\x{92}/gsi;
    $wiki =~ s/\x{c3}\x{af}\x{c6}\x{92}\x{c2}\x{a0}/\x{e2}\x{86}\x{92}/gsi;
    $wiki =~ s/\x{ef}\x{83}\x{a0}/\x{e2}\x{86}\x{92}/gsi;
    $wiki =~ s/\x{ef}\x{80}\x{b0}/\x{e2}\x{86}\x{92}/gsi;
    ## LEFTWARDS arrow
    $wiki =~ s/\x{EF}\x{192}\x{178}/\x{e2}\x{86}\x{90}/gsi;
    $wiki =~ s/\x{c3}\x{af}\x{c6}\x{92}\x{c5}\x{b8}/\x{e2}\x{86}\x{90}/gsi;
    ## double arrow:
    $wiki =~ s/\x{EF}\x{192}\x{17E}/\x{e2}\x{87}\x{92}/gsi;
    ## 3 points
    $wiki =~ s/\x{E2}\x{20AC}\x{A6}/.../gsi;
    ## black circle
    $wiki =~ s/\x{EF}\x{201A}\x{B7}/\x{e2}\x{97}\x{8f}/gsi;
    $wiki =~ s/\x{c3}\x{af}\x{e2}\x{80}\x{9a}\x{c2}\x{b7}/\x{e2}\x{97}\x{8f}/gsi;
    $wiki =~ s/\x{ef}\x{82}\x{b7}/\x{e2}\x{97}\x{8f}/gsi;
    ## black square
    $wiki =~ s/\x{c3}\x{af}\x{e2}\x{80}\x{9a}\x{c2}\x{a7}/\x{e2}\x{96}\x{a0}/gsi;
    ## CHECK MARK
    $wiki =~ s/\x{EF}\x{81}\x{90}/\x{e2}\x{9c}\x{94}/gsi;
    $wiki =~ s/\x{ef}\x{83}\x{bc}/\x{e2}\x{9c}\x{94}/gsi;
    $wiki =~ s/\x{ef}\x{83}\x{96}/\x{e2}\x{9c}\x{94}/gsi;
    $wiki =~ s/\x{EF}\x{192}\x{bc}/\x{e2}\x{9c}\x{94}/gsi;

    ## BALLOT X
    $wiki =~ s/\x{EF}\x{81}\x{8F}/\x{e2}\x{9c}\x{98}/gsi;
    $wiki =~ s/\x{EF}\x{192}\x{BB}/\x{e2}\x{9c}\x{98}/gsi;
    $wiki =~ s/\x{c3}\x{af}\x{c6}\x{92}\x{c2}\x{bb}/\x{e2}\x{9c}\x{98}/gsi;
    ## CIRCLE BACKSLASH
    $wiki =~ s/\x{EF}\x{81}\x{2014}/\x{e2}\x{9c}\x{98}/gsi;
    ## some strange spaces
    $wiki =~ s/\x{c2}\x{a0}/ /gsi;

    $wiki =~ s/\x{ef}\x{80}\x{b2}/2/gsi;
    $wiki =~ s/\x{ef}\x{80}\x{b0}/0/gsi;
    ## strangem, no apperant use
    $wiki =~ s/\x{4}//gsi;
    $wiki =~ s/\x{5}//gsi;

    return $wiki;
}

sub get_wiki_images {
    my ($wiki, $image_files, $dir) = @_;
    INFO "\tFix images from wiki.\n";
    while ($wiki =~ m/(\[\[Image:)([[:print:]].*?)(\]\])/g ) {
	my $pic_name = uri_unescape( $2 );
	$pic_name =~ s/(.*?)(\|.*)/$1/;
	my $info = image_info("$dir/$pic_name");
	if (my $error = $info->{error}) {
	    INFO "Can't parse image info for dir \"$dir\", file \"$pic_name\":\n\t $error.\n";
# 	    LOGDIE "" if $dir !~ m/CMS:MIND-IPhonEX CMS 80.00.020/;
	    next;
	}
	push (@$image_files,  "$dir/$pic_name");
    }
    return $image_files;
}

sub fix_wiki_footers {
    my $wiki = shift;
    INFO "\tFix footers from wiki.\n";
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
	my $striped_str =  HTML::TreeBuilder->new_from_content($string)->guts->as_text();
	my $new_string = "\[$start"."_"."$striped_str\|$striped_str$end\]";
	substr($newwiki, $found_string_end_pos - length($found_string) + $count, length($found_string)) = $new_string;
	$count += length($new_string) - length($found_string);
    }
    $newwiki =~ s/<div id="(sdfootnote[[:digit:]]{1,})">([\s]{1,})\[\[#([[:print:]].*?)\|([[:print:]].*?)\]\](.*?)<\/div>/<span id="$3">$4: $5<\/span>\n\n/gsi;
    return $newwiki;
}

sub fix_wiki_links_menus {
    my $wiki = shift;
    INFO "\tFix links to menus from wiki.\n";
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
#     INFO "\tFix urls from wiki.\n";
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
    INFO "\tFix links to SC.\n";
    my $newwiki = $wiki;
    my $count = 0;
    while ($wiki =~ m/(\[\[Image:[[:print:]]*?(B|I|F|H|R|D|E|G|S|T|Z|K|A|P)[[:digit:]]{4,}[[:print:]]*?\]\])|(\b(B|I|F|H|R|D|E|G|S|T|Z|K|A|P)[[:digit:]]{4,}\b)/g ) {
	my $found_string = $&;
	my $found_string_end_pos = pos($wiki);

	next if ($found_string =~ /^\[\[Image:/);
	DEBUG "\tSC link: $found_string\n";
	my $new_string = " [[SC:$found_string|$found_string]] ";
	substr($newwiki, $found_string_end_pos - length($found_string)+$count, length($found_string)) = $new_string;
	$count += length($new_string) - length($found_string);
    }
    $wiki = $newwiki;
    return $wiki;
}

sub get_deployment_conf {
    my $wiki_txt = shift;
    my $result = "";
    if ($wiki_txt =~ /(^|\n)(=+)([^\n]*?deployment.*?\2\n)(.*)/ims){
	my $heading = "$2$3";
	my $heading_length = length($2);
	my $found_string = $&;
	my $txt = "$4";
	$txt =~ s/\n={1,$heading_length}[^=].*//ms;
	$txt = "$heading$txt";
	return if $txt =~ m/^\n*=+(Deployment consideration( \(mandatory for Payment Manager\))?\.?|Deployment configuration &amp; consideration\.?)=+\n+(<font color="#0000ff">)?(Add all assumptions, settings, actions, etc that are relevant for the correct deployment and use of the system\.?|Specify all configuration, and consideration that are relevant for correct deployment of the system\.?)?(TBD|NR|NA|N\/?R|N\/?A)?\.?\s*(<\/font>)?\n*(TBD|NR|NA|N\/?R|N\/?A)?\.?\s*\n*$/gsi;
	INFO "\t Found some deployment stuff.\n";
	return $txt;
    }
    return;
}

return 1;
