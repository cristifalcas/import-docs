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
    ## $general_categories_hash->{5.01.019}->{5.01} means that 5.01.019 will be in 5.01 category
    $general_categories_hash->{$ver}->{$main} = 1 if $ver ne "" && $ver ne $main;
    $general_categories_hash->{$ver}->{$big_ver} = 1 if $ver ne "" && $big_ver ne "";
    $general_categories_hash->{$ver}->{$customer} = 1 if $big_ver ne "" && $customer ne "";
    $general_categories_hash->{$ver}->{$dir_type} = 1 if $big_ver ne "" && $dir_type ne "";

    $general_categories_hash->{$main}->{$big_ver} = 1 if $main ne "" && $big_ver ne "";
    $general_categories_hash->{$main}->{$customer} = 1 if $main ne "" && $customer ne "";
    $general_categories_hash->{$main}->{$dir_type} = 1 if $main ne "" && $dir_type ne "";
    $general_categories_hash->{$main}->{'Mind Documentation autoimport'} = 1 if $main ne "";

    $general_categories_hash->{$customer}->{$dir_type} = 1 if $customer ne "" && $dir_type ne "";
    $general_categories_hash->{$customer}->{'MIND_Customers'} = 1 if $customer ne "";
    $general_categories_hash->{$customer}->{'Mind Documentation autoimport'} = 1 if $customer ne "";

    $general_categories_hash->{$big_ver}->{'Mind Documentation autoimport'} = 1 if $big_ver ne "";
    $general_categories_hash->{$dir_type}->{'Mind Documentation autoimport'} = 1 if $dir_type ne "";
    ## SC
    $general_categories_hash->{$main}->{'SCDocs'} = 1 if $main =~ /^SC:/;
    $general_categories_hash->{$customer}->{'SCDocs'} = 1 if $customer =~ /^SC:/;
    $general_categories_hash->{$big_ver}->{'SCDocs'} = 1 if $big_ver =~ /^SC:/;
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
# next if $node ne 'B19868';
	die "Can't find files_info or General wiki.\n" if (! -e "$path_files/$node/$files_info_file" || ! -e "$path_files/$node/$general_wiki_file");

	my $md5 = "$node";
	open(FH, "$path_files/$node/$files_info_file") || die("Could not open file!");
	my @data=<FH>;
	chomp @data;
	close(FH);
# print "$node\n";
	my @categories = ();
	my $info_crt_h ;
	foreach my $line (@data) {
# 	    $line .= " " if $line =~ m/^Categories(.*)\;$/;
	    $line .= " " if $line =~ m/^(.*)\;$/;
	    my @tmp = split ';', $line;
	    chomp @tmp;

	    if ($tmp[0] eq "Categories") {
next;
# print "$line\n";
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
# 			$w = "6.60.003 SP24.002" if $w eq "6.60.003 SP24.002 P";
# 			$w = "6.01.004 SP43.010" if $w eq "6.01.004 SP.43.010";
# 			$w = "6.50.009 SP05.010" if $w eq "6.50.009, SP05.010";
# 			$w = "6.50.010 SP09.002" if $w eq "6.50.010.SP09.002";
# 			$w = "6.60.003 SP17.003" if $w eq "6.60.003 SO17.003";
# 			$w = "6.60.003 SP30.004" if $w eq "6.60.003 SP30 30.004";

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
# 		$tmp[1] =~ s/\s*$//g;
# 		$tmp[2] =~ s/\s*$//g;
# 		$tmp[3] =~ s/\s*$//g;
# 		my $customer = $tmp[1] || "";
# 		my $full_ver = $tmp[2] || "";
# 		my $main_ver = $full_ver;
# 		$main_ver =~ s/([[:digit:]]{1,})(\.[[:digit:]]{1,})?(.*)/$1$2/;
#
# 		($big_ver, $main, $ver, $ver_fixed, $ver_sp, $ver_id) = WikiCommons::check_vers ($main_ver, $full_ver);
# 		$main = $main.$url_sep."SC" if $main ne "";
# 		$ver = $ver.$url_sep."SC" if $ver ne "";
# 		$ver_fixed = $ver_fixed.$url_sep."SC" if $ver_fixed ne "";
# 		$big_ver = $big_ver.$url_sep."SC" if $big_ver ne "";
# 		$ver_sp = $ver_sp.$url_sep."SC" if $ver_sp ne "";
# # 		$ver_without_sp = $ver_without_sp.$url_sep."SC" if $ver_without_sp ne "";
# 		$customer = $customer.$url_sep."SC" if $customer ne "";
# 		generate_categories( $ver_fixed, $main, $big_ver, $customer, "SCDocs");
#
# 		$tmp[1] = $customer;
# 		$tmp[2] = $ver_fixed;
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
