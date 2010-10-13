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
	my $info_crt_h = {};
	foreach my $line (@data) {
	    $line .= " " if $line =~ m/\;$/;
	    my @tmp = split ';', $line;
	    $md5 .= "$tmp[2]" if defined $tmp[2];
	    die "Wrong number of fields for line $line in $node/$files_info_file.\n" if @tmp<4;

# print "$node: $tmp[0]\n";
	    if ($tmp[0] eq "Categories") {
		my $customer = $tmp[1] || "";
		$customer =~ s/^customer //;
		my $full_ver = $tmp[2] || "";
		$full_ver =~ s/^version //;
		my $main_ver = $full_ver;
		$main_ver =~ s/([[:digit:]]{1,})(\.[[:digit:]]{1,})?(.*)/$1$2/;
# print "xxx $node _$main_ver _$full_ver.\n";
		# $main, $ver
		my ($main, $ver, $ver_fixed, $big_ver, $ver_sp, $ver_without_sp) = WikiCommons::check_vers ($main_ver, $full_ver);
# 		# $ver, $main, $big_ver, $customer,
		WikiCommons::generate_categories( $ver_without_sp, $main, $big_ver, $customer, "SC docs");
# 			foreach my $sec_key (keys %{$info_crt_h->{$key}}) {
# 			    push @categories, $info_crt_h->{$key}->{$sec_key};
# 			}
# print Dumper(@categories);
	    }
	    $info_crt_h->{$tmp[0]}->{'name'} = "$tmp[1]";
	    $info_crt_h->{$tmp[0]}->{'size'} = "$tmp[2]";
	    $info_crt_h->{$tmp[0]}->{'revision'} = "$tmp[3]";
	}

# 	foreach my $line (@data) {
# 	    my @info = split ';', $line;
# 	    $md5 .= "$info[2]" if defined $info[2];
# 	}
	$pages_toimp_hash->{"SC:$node"} = [$md5, "$node", "$info_crt_h", "real", \@categories];
    }
    print "\tDone $count from a total of $total.\t". (WikiCommons::get_time_diff) ."\n" if ($count%500 != 0);
    print "+Searching for files in SC dir.\t". (WikiCommons::get_time_diff) ."\n";
    return $pages_toimp_hash;
}

return 1;
