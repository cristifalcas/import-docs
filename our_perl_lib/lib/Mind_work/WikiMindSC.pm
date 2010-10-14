package WikiMindSC;

use warnings;
use strict;

use Data::Dumper;

our $pages_toimp_hash = {};

sub new {
    my $class = shift;
    my $self = { path_files => shift , url_sep => shift};
    bless($self, $class);
    return $self;
}

sub get_documents {
    my $self = shift;
    my $path_files = $self->{path_files};
    opendir(DIR, "$path_files") || die("Cannot open directory $path_files.\n");
    my @all = grep { (!/^\.\.?$/) && -d "$path_files/$_" } readdir(DIR);
    closedir(DIR);

    my $general_wiki_file = "General_info.wiki";
    my $files_info_file = "files_info.txt";
    my $total = @all;
    my $count = 0;
    my $url_sep = WikiCommons::get_urlsep;
    print "-Searching for files in SC dir.\t". (WikiCommons::get_time_diff) ."\n";
    foreach my $node (sort @all) {
	$count++;
	print "\tDone $count from a total of $total.\t". (WikiCommons::get_time_diff) ."\n" if ($count%1000 == 0);
# next if $node ne 'B71488';
	die "Can't find files_info or General wiki.\n" if (! -e "$path_files/$node/$files_info_file" || ! -e "$path_files/$node/$general_wiki_file");

	my $md5 = "$node";
	open(FH, "$path_files/$node/$files_info_file") || die("Could not open file!");
	my @data=<FH>;
	chomp @data;
	close(FH);


	my @categories = ();
	my $info_crt_h ;
	foreach my $line (@data) {
# 	    $line .= " " if $line =~ m/^Categories(.*)\;$/;
	    $line .= " " if $line =~ m/^(.*)\;$/;
	    my @tmp = split ';', $line;
	    chomp @tmp;
	    $md5 .= "$tmp[2]" if defined $tmp[2];
	    die "Wrong number of fields for line $line in $node/$files_info_file.\n" if @tmp<4;

	    if ($tmp[0] eq "Categories") {
		$tmp[1] =~ s/^customer //i;
		$tmp[1] =~ s/\s*$//g;
		$tmp[2] =~ s/^version //i;
		$tmp[2] =~ s/\s*$//g;
		$tmp[3] =~ s/\s*$//g;
		my $customer = $tmp[1] || "";
		my $full_ver = $tmp[2] || "";
		my $main_ver = $full_ver;
		$main_ver =~ s/([[:digit:]]{1,})(\.[[:digit:]]{1,})?(.*)/$1$2/;

		my ($main, $ver, $ver_fixed, $big_ver, $ver_sp, $ver_without_sp) = WikiCommons::check_vers ($main_ver, $full_ver);
		$main = $main.$url_sep."SC" if $main ne "";
		$ver = $ver.$url_sep."SC" if $ver ne "";
		$ver_fixed = $ver_fixed.$url_sep."SC" if $ver_fixed ne "";
		$big_ver = $big_ver.$url_sep."SC" if $big_ver ne "";
		$ver_sp = $ver_sp.$url_sep."SC" if $ver_sp ne "";
		$ver_without_sp = $ver_without_sp.$url_sep."SC" if $ver_without_sp ne "";
		$customer = $customer.$url_sep."SC" if $customer ne "";
		WikiCommons::generate_categories( $ver_without_sp, $main, $big_ver, $customer, "SCDocs");

		$tmp[1] = $customer;
		$tmp[2] = $ver_without_sp;
	    }
	    $info_crt_h->{$tmp[0]}->{'name'} = "$tmp[1]";
	    $info_crt_h->{$tmp[0]}->{'size'} = "$tmp[2]";
	    $info_crt_h->{$tmp[0]}->{'revision'} = "$tmp[3]";
	}
	$pages_toimp_hash->{"SC:$node"} = [$md5, "$node", $info_crt_h, "real", \@categories];
    }
    print "\tDone $count from a total of $total.\t". (WikiCommons::get_time_diff) ."\n" if ($count%500 != 0);
    print "+Searching for files in SC dir.\t". (WikiCommons::get_time_diff) ."\n";
    return $pages_toimp_hash;
}

return 1;
