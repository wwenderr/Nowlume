#!/usr/bin/perl
use strict;
use warnings;
use DynaLoader;

my $library = shift @ARGV or die "Missing helper library path\n";
my $symbol = shift @ARGV or die "Missing helper symbol\n";
my $handle = DynaLoader::dl_load_file($library, 0)
    or die "Could not load helper library: " . DynaLoader::dl_error() . "\n";
my $address = DynaLoader::dl_find_symbol($handle, $symbol)
    or die "Could not find helper symbol: $symbol\n";
my $function = DynaLoader::dl_install_xsub("main::$symbol", $address);
&$function();
