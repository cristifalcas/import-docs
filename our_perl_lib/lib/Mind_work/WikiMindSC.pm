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
# next if $node ne 'B17982';
	if (! -e "$path_files/$node/$files_info_file" || ! -e "$path_files/$node/$general_wiki_file") {
	    die "Can't find files_info or General wiki: $path_files/$node.\n";
	    next;
	}

	my $md5 = "$node";
	open(FH, "$path_files/$node/$files_info_file") || die("Could not open file!");
	my @data=<FH>;
	chomp @data;
	close(FH);
	my @categories = ();
	my $info_crt_h ;
# 	my $url_namespace = "SC_iPhonex_Bug";
	my $url_namespace = "";
	foreach my $line (@data) {
	    $line .= " " if $line =~ m/^(.*)\;$/;
	    my @tmp = split ';', $line;
	    chomp @tmp;

	    if ($tmp[0] eq "Categories") {
		foreach my $q (@tmp) {
		    $q =~ s/(^\s*)|(\s*$)//g;
		    next if $q !~ "^ChangeType";
		    my $sc_type = $q;
		    $sc_type =~ s/^ChangeType\s+//;
		    push @categories, $q;
		    if ($sc_type ne "Change" && $sc_type ne "Bug") {
			print "\tSC type is unknown: $sc_type.\n";
			$sc_type = "Bug";
		    }
		    if ( $path_files =~ m/canceled/i ) {
# print "$path_files\n";exit 1;
			$url_namespace = "SC_Canceled";
		    } elsif ($node =~ m/^B/i) {
			$url_namespace = "SC_iPhonex_$sc_type";
		    } elsif ($node =~ m/^F/i) {
			$url_namespace = "SC_SIP_$sc_type";
		    } elsif ($node =~ m/^I/i) {
			$url_namespace = "SC_Sentori_$sc_type";
		    } elsif ($node =~ m/^H/i) {
			$url_namespace = "SC_Infrastructure_$sc_type";
		    } elsif ($node =~ m/^R/i) {
			$url_namespace = "SC_PaymentManager_$sc_type";
		    } elsif ($node =~ m/^D/i) {
			$url_namespace = "SC_PhonexONE_$sc_type";
		    } elsif ($node =~ m/^T/i) {
			$url_namespace = "SC_Nagios_$sc_type";
		    } elsif ($node =~ m/^Z/i) {
			$url_namespace = "SC_Other_$sc_type";
		    } elsif ($node =~ m/^K/i) {
			$url_namespace = "SC_Abacus_$sc_type";
		    } elsif ($node =~ m/^A/i) {
			$url_namespace = "SC_PhonEX_$sc_type";
		    } elsif ($node =~ m/^P/i) {
			$url_namespace = "SC_Plugins_$sc_type";
		    } else {
			$url_namespace = "SC_iPhonex_$sc_type";
die "no namespace here 1: $node.\n".Dumper(@data);
		    }
		    push @categories, "RealNameSpace ".$url_namespace;
		    next;

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
	    ## like this in order to not update everything after we added the date to docs
	    die "Wrong number of fields for line $line in $node/$files_info_file.\n" if @tmp < 4 || @tmp > 5;
	    $info_crt_h->{$tmp[0]}->{'name'} = "$tmp[1]";
	    $info_crt_h->{$tmp[0]}->{'size'} = "$tmp[2]";
	    $info_crt_h->{$tmp[0]}->{'revision'} = "$tmp[3]";
	    ## like this in order to not update everything after we added the date to docs
	    $info_crt_h->{$tmp[0]}->{'date'} = "$tmp[4]" if defined $tmp[4];
	}

die "no namespace here 2: $node.\n".Dumper(@data) if $url_namespace eq "";
	$pages_toimp_hash->{"$url_namespace:$node"} = [$md5." redirect", "$node", $info_crt_h, "real", \@categories];
	$pages_toimp_hash->{"SC:$node"} = [$md5, "$node", $info_crt_h, "real", \@categories];
    }
    print "\tDone $count from a total of $total.\t". (WikiCommons::get_time_diff) ."\n" if ($count%500 != 0);
    print "+Searching for files in SC dir.\t". (WikiCommons::get_time_diff) ."\n";
    return $pages_toimp_hash;
}

return 1;
