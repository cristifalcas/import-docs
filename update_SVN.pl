#!/usr/bin/perl -w
#LD_LIBRARY_PATH=./instantclient_11_2/ perl ./oracle.pl
use warnings;
use strict;
$SIG{__WARN__} = sub { die @_ };

my @crt_timeData = localtime(time);
foreach (@crt_timeData) {$_ = "0$_" if($_<10);}
print "Start: ". ($crt_timeData[5]+1900) ."-".($crt_timeData[4]+1)."-$crt_timeData[3] $crt_timeData[2]:$crt_timeData[1]:$crt_timeData[0].\n";

## ~ 10 hours first run
use Cwd 'abs_path','chdir';
use File::Basename;
use lib (fileparse(abs_path($0), qr/\.[^.]*/))[1]."our_perl_lib/lib";
# use DBI;
use File::Path qw(make_path remove_tree);
use Data::Dumper;
$Data::Dumper::Sortkeys = 1;
Log::Log4perl->easy_init({ level   => $DEBUG,
#                            file    => ">>test.log" 
# 			   layout   => "%d [%5p] (%6P) [%rms] [%M] - %m{chomp}\t%x\n",
			   layout   => "%5p (%6P) %m{chomp}\n",
});
use File::Listing qw(parse_dir);
use File::Find;
use File::Copy;
use POSIX;
use Mind_work::WikiCommons;

our $svn_user = 'svncheckout';
our $svn_pass = 'svncheckout';
my $svn_url = "";
our @search_in_dirs = ("Documents", "Scripts");
our $svn_helper_file = "svn_helper_trunk_info.txt";
our $mind_ver_min = "5.00";

LOGDIE "We need the destination path.\n" if ( $#ARGV != 0 );
our ($to_path) = @ARGV;
WikiCommons::makedir ("$to_path", 0);
$to_path = abs_path("$to_path");

sub get_dir {
    my $dir = shift;
    my $info = {};
    opendir(DIR, "$dir") || LOGDIE "Cannot open directory $dir: $!.\n";
    my @dirs = grep { (!/^\.\.?$/) && -d "$dir"} readdir(DIR);
    closedir(DIR);
    return @dirs;
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
# `svn upgrade "$local_url"` if -d $local_url;
		INFO "checkout:\n\t$svn_url\n\t\tto\n\t$local_url\n" ;
		WikiCommons::makedir ("$local_url", 0);
		my $text = "SVN_URL = $svn_url\nLOCAL_SVN_PATH = $local_url\n";
		WikiCommons::write_file("$local_url/$svn_helper_file", $text);
		WikiCommons::svn_checkout($svn_url, $local_url, $svn_pass, $svn_user);
	    }
	}
    } else {
# `svn upgrade "$local"` if -d $local;
	INFO "checkout:\n\t$svn\n\t\tto\n\t$local\n" ;
	WikiCommons::makedir ("$local", 0);
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
	INFO "Remove dir $local/$_.\n";
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

sub docs_sentori {
    my $url = shift;
    my $local_path = "$to_path/Docs_Sentori";
    get_documentation($url, $local_path, 1);
}

sub docs_pos {
    my $url = shift;
    my $local_path = "$to_path/Docs_POS";
    get_documentation($url, $local_path, 1);
}

sub docs_phonex {
    my $url = shift;
    my $local_path = "$to_path/Docs_Phonex";
    get_documentation($url, $local_path, 1);
}

sub docs_cms {
    my $url = shift;
    my $local_path = "$to_path/Docs_CMS";
    get_documentation($url, $local_path, 1);
}

sub docs_sipserver {
    my $url = shift;
    my $local_path = "$to_path/Docs_SIPServer";
    get_documentation($url, $local_path, 1);
}

sub projects_pmg {
    my $url = shift;
    my $local_path = "$to_path/Docs_PaymentManager";
    get_documentation($url, $local_path, 1);
}

sub projects_pmg_deployment {
    my $url = shift;
    my $local_path = "$to_path/Docs_PaymentManager_Deployment";
    get_documentation($url, $local_path, 1);
}

my $original_to_path = $to_path;
$to_path = "$original_to_path/svn_mind_docs";
$svn_url = 'http://10.10.4.4:8080/svn/repos/trunk/Projects/PaymentManager/1.00/V1.00/Documents/';
projects_pmg ("$svn_url");
$svn_url = 'http://10.10.4.4:8080/svn/repos/trunk/Projects/PaymentManager/Deployment/';
projects_pmg_deployment ("$svn_url");
$svn_url = 'http://10.10.4.4:8080/svn/docs/repos/trunk/Documentation/iPhonEX%20Documents';
docs_sipserver("$svn_url/SIPServer/");
$svn_url = 'http://10.10.4.4:8080/svn/repos/trunk/Projects/iPhonEX';
INFO "Start working for projects.\n";
projects ($svn_url);
INFO "Start working for projects_common.\n";
projects_common ("$svn_url/Common/");
INFO "Start working for projects_customization.\n";
projects_customization ("$svn_url/Customizations/");
INFO "Start working for projects_deployment.\n";
projects_deployment ("$svn_url/Deployment/");
INFO "Start working for projects_deployment_common.\n";
projects_deployment_common ("$svn_url/Deployment/Common/");
INFO "Start working for projects_deployment_customization.\n";
projects_deployment_customization ("$svn_url/Deployment/Customization/");

$svn_url = 'http://10.10.4.4:8080/svn/docs/repos/trunk/Documentation/iPhonEX%20Documents';
INFO "Start working for docs.\n";
docs ("$svn_url/iPhonEX");
INFO "Start working for docs_customization.\n";
docs_customization ("$svn_url/iPhonEX/Customizations/");

$svn_url = 'http://10.10.4.4:8080/svn/docs/repos/trunk/Documentation';
INFO "Start working for docs_pos.\n";
docs_pos("$svn_url".'/POS%20Documents/');

$to_path = "$original_to_path/svn_cms_docs";
INFO "Start working for docs_sentori.\n";
docs_sentori("$svn_url/Sentori/");
INFO "Start working for docs_phonex.\n";
docs_phonex("$svn_url".'/PhonEX%20Documents/');
# $svn_url = 'http://10.10.4.4:8080/svn/docs/repos/trunk/Documentation/iPhonEX%20Documents';
INFO "Start working for docs_cms.\n";
docs_cms ("$svn_url".'/iPhonEX%20Documents/CMS/');
INFO "DONE.\n";
