#!/usr/bin/perl -w
#LD_LIBRARY_PATH=./instantclient_11_2/ perl ./oracle.pl
use warnings;
use strict;
$SIG{__WARN__} = sub { die @_ };

## ~ 10 hours first run
use lib "./our_perl_lib/lib";
# use DBI;
use File::Path qw(make_path remove_tree);
use Data::Dumper;
$Data::Dumper::Sortkeys = 1;
use File::Basename;
use File::Listing qw(parse_dir);
use File::Find;
use File::Copy;
use POSIX;
use Cwd 'abs_path','chdir';
use Mind_work::WikiCommons;

our $svn_user = 'svncheckout';
our $svn_pass = 'svncheckout';
my $svn_url = "";
our @search_in_dirs = ("Documents", "Scripts");
our $svn_helper_file = "svn_helper_trunk_info.txt";
our $mind_ver_min = "5.00";

die "We need the destination path.\n" if ( $#ARGV != 0 );
our ($to_path) = @ARGV;
WikiCommons::makedir ("$to_path");
$to_path = abs_path("$to_path");
# 0758062144

sub get_dir {
    my $dir = shift;
    my $info = {};
    opendir(DIR, "$dir") || die "Cannot open directory $dir: $!.\n";
    my @dirs = grep { (!/^\.\.?$/) && -d "$dir"} readdir(DIR);
    closedir(DIR);
    return @dirs;
}

sub get_diff {
    my (@array1, @array2) = @_;
    my (@union, @intersection, @difference) = ();
    my %count = ();
    foreach my $element (@array1, @array2) { $count{$element}++ }
    foreach my $element (keys %count) {
        push @union, $element;
        push @{ $count{$element} > 1 ? \@intersection : \@difference }, $element;
    }
    return (\@union, \@intersection, \@difference);
}

sub is_version_ok {
    my $str = shift;
    $str =~ s/((^v)|(\/$))//i;
    $str =~ s/^([0-9]{1,}(\.[0-9]{1,})?)(.*?)$/$1/;
    return 0 if $str !~ m/^[0-9]{1,}(\.[0-9]{1,})?$/;
    return $str > $mind_ver_min;
}

sub get_documentation {
    my ($svn, $local, $in_search_dir) = @_;

    if (! defined $in_search_dir) {
	foreach my $doc_dir (@search_in_dirs){
	    my $svn_url = "$svn/$doc_dir";
	    my $local_url = "$local/$doc_dir";
	    if ( defined WikiCommons::svn_list($svn_url, $svn_pass, $svn_user) ){
		print "checkout:\n\t$svn_url\n\t\tto\n\t$local_url\n" ;
		WikiCommons::makedir ("$local_url");
		my $text = "SVN_URL = $svn_url\nLOCAL_SVN_PATH = $local_url\n";
		WikiCommons::write_file("$local_url/$svn_helper_file", $text);
		WikiCommons::svn_checkout($svn_url, $local_url, $svn_pass, $svn_user);
	    }
	}
    } else {
	print "checkout:\n\t$svn\n\t\tto\n\t$local\n" ;
	WikiCommons::makedir ("$local");
	my $text = "SVN_URL = $svn\nLOCAL_SVN_PATH = $local\n";
	WikiCommons::write_file("$local/$svn_helper_file", $text);
	WikiCommons::svn_checkout($svn, $local, $svn_pass, $svn_user);
    }
}

sub clean_path {
    my ($svn, $local) = @_;
    my @local_dirs = ();
    @local_dirs = get_dir($local) if -d "$local";
    my @svn_dirs = split "\n", WikiCommons::svn_list($svn, $svn_pass, $svn_user);
    my ($only_on_local, $only_on_svn, $common) = WikiCommons::array_diff( \@local_dirs, \@svn_dirs);
    foreach (@$only_on_local) {
	print "Remove dir $local/$_.\n";
	remove_tree("$local/$_");
    }
    return \@svn_dirs;
}

sub projects {
    my $url = shift;
    my $local_path = "$to_path/Projects";
    my $svn_dirs = clean_path($url, $local_path);
    foreach my $dir (@$svn_dirs) {
	next if ! is_version_ok($dir);
	my $vers = clean_path("$url/$dir", "$local_path/$dir");
	foreach my $ver (@$vers) {
	    get_documentation("$url/$dir/$ver", "$local_path/$dir/$ver");
	}
    }
}

sub projects_deployment {
    my $url = shift;
    my $local_path = "$to_path/Projects_Deployment";
    my $svn_dirs = clean_path($url, $local_path);
    foreach my $dir (@$svn_dirs) {
	next if ! is_version_ok($dir);
	    get_documentation("$url/$dir", "$local_path/$dir", 1);
    }
}

sub projects_customization {
    my $url = shift;
    my $local_path = "$to_path/Projects_Customizations";
    my $svn_dirs = clean_path($url, $local_path);
    foreach my $dir (@$svn_dirs) {
	my $vers = clean_path("$url/$dir", "$local_path/$dir");
	foreach my $ver (@$vers) {
	    get_documentation("$url/$dir/$ver", "$local_path/$dir/$ver");
	}
    }
}

sub projects_deployment_customization {
    my $url = shift;
    my $local_path = "$to_path/Projects_Deployment_Customization";
    get_documentation($url, $local_path, 1);
}

sub projects_common {
    my $url = shift;
    my $local_path = "$to_path/Projects_Common";
    get_documentation($url, $local_path);
}

sub projects_deployment_common {
    my $url = shift;
    my $local_path = "$to_path/Projects_Deployment_Common";
    get_documentation($url, $local_path, 1);
}

sub docs {
    my $url = shift;
    my $local_path = "$to_path/Docs";
    my $svn_dirs = clean_path($url, $local_path);
    foreach my $dir (@$svn_dirs) {
	next if ! is_version_ok($dir);
	get_documentation("$url/$dir/", "$local_path/$dir/", 1);
    }
}

sub docs_customization {
    my $url = shift;
    my $local_path = "$to_path/Docs_Customizations";
    get_documentation($url, $local_path, 1);
}

$svn_url = 'http://10.10.4.4:8080/svn/repos/trunk/Projects/iPhonEX';
# $svn_url = 'http://10.10.4.4:8080/svn/repos/trunk/Projects/Plugins/PluginGenerator/';
projects ($svn_url);
projects_common ("$svn_url/Common/");
projects_customization ("$svn_url/Customizations/");
projects_deployment ("$svn_url/Deployment/");
projects_deployment_common ("$svn_url/Deployment/Common/");
projects_deployment_customization ("$svn_url/Deployment/Customization/");

$svn_url = 'http://10.10.4.4:8080/svn/docs/repos/trunk/Documentation/iPhonEX%20Documents/iPhonEX';
docs ($svn_url);
docs_customization ("$svn_url/Customizations/");

# http://10.10.4.4:8080/svn/docs/repos/trunk/Documentation/Sentori/
# http://10.10.4.4:8080/svn/docs/repos/trunk/Documentation/POS%20Documents/
# http://10.10.4.4:8080/svn/docs/repos/trunk/Documentation/PhonEX%20Documents/
# http://10.10.4.4:8080/svn/docs/repos/trunk/Documentation/iPhonEX%20Documents/SIPServer/
