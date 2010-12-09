package WikiMindSC;

use warnings;
use strict;

use Data::Dumper;
$Data::Dumper::Sortkeys = 1;

our $pages_toimp_hash = {};
our $general_categories_hash = {};

sub new {
    my $class = shift;
    my $self = { path_files => shift , url_sep => shift};
    bless($self, $class);
    return $self;
}

sub get_categories {
    return $general_categories_hash;
}

sub generate_categories {
    my ($ver, $main, $big_ver, $customer, $dir_type) = @_;
#     ## $general_categories_hash->{5.01.019}->{5.01} means that 5.01.019 will be in 5.01 category
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
# next if $node ne 'F70051';
	die "Can't find files_info or General wiki.\n" if (! -e "$path_files/$node/$files_info_file" || ! -e "$path_files/$node/$general_wiki_file");

	my $md5 = "$node";
	open(FH, "$path_files/$node/$files_info_file") || die("Could not open file!");
	my @data=<FH>;
	chomp @data;
	close(FH);
	my @categories = ();
	my $info_crt_h ;
	foreach my $line (@data) {
	    $line .= " " if $line =~ m/^(.*)\;$/;
	    my @tmp = split ';', $line;
	    chomp @tmp;

	    if ($tmp[0] eq "Categories") {
next;
		foreach my $q (@tmp) {
		    $q =~ s/(^\s*)|(\s*$)//g;
		    next if $q eq "Categories" || $q =~ m/^\s*$/ || $q eq "customer" || $q eq "version";
		    if ($q =~ m/^customer /i){
			my $customer = $q; $customer =~ s/^customer //i;
			next if $customer =~ m/^\s*$/;
			$customer = $customer.$url_sep."SC";
			push @categories, "customer ".$customer;
		    } elsif ($q =~ m/^version /i) {
			my $w = $q; $w =~ s/^version //i; $w =~ s/\.$//;
			next if $w =~ m/^\s*$/;
			$w =~ s/\s+p\s*//i;

			my ($big_ver, $main, $ver, $ver_fixed, $ver_sp, $ver_id) = WikiCommons::check_vers ( $w, $w);
			$big_ver = $big_ver.$url_sep."SC";
			$main = $main.$url_sep."SC";
			$ver_fixed = $ver_fixed.$url_sep."SC";
			push @categories, "version_b ".$big_ver;
			push @categories, "version_m ".$main;
			push @categories, "version_v ".$ver_fixed;
		    } else {
			die "Unknown category in $line: $q.\n";
		    }
		}
		next;
	    }

	    $md5 .= "$tmp[2]" if defined $tmp[2];
	    die "Wrong number of fields for line $line in $node/$files_info_file.\n" if @tmp<4;
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
