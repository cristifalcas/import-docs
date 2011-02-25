#!/usr/bin/perl

#find ./Documentation/sc/ -type f -iname General_info.wiki -exec \
undef $/;
open FILE, "<" . "@ARGV[0]";
$buf = <FILE>;
close FILE;
#print "@ARGV[0]\n";
print "@ARGV[0]\n"
    if $buf =~ m/{\| class=\"wikitable\"\n\| \'\'\'Type\'\'\'\n\| Bug\n\|-\n\| \'\'\'Category\'\'\'/gm;
