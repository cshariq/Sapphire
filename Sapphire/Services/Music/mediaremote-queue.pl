#!/usr/bin/perl
#
# mediaremote-queue.pl FRAMEWORK_PATH FUNCTION
#
# Runs one SapphireMediaQueue.framework function inside /usr/bin/perl, a
# platform binary MediaRemote still answers (see SapphireMediaQueue.m).
# Parameters are passed as SMQ_* environment variables; output is one JSON line.

use strict;
use warnings;
use DynaLoader;
use File::Basename;
use File::Spec;

sub fail {
  my ($message) = @_;
  print "{\"ok\":false,\"error\":\"$message\"}\n";
  exit 1;
}

my $framework_path = shift @ARGV or fail("missing framework path");
my $function = shift @ARGV or fail("missing function");
fail("invalid function") unless $function =~ /^(queue|play_item|remove_item|clear_up_next|insert|play_now)$/;

my $name = File::Basename::basename($framework_path);
$name =~ s/\.framework$// or fail("not a framework");
my $binary = File::Spec->catfile($framework_path, $name);
fail("framework binary missing") unless -e $binary;

my $handle = DynaLoader::dl_load_file($binary, 0) or fail("failed to load framework");
my $symbol = DynaLoader::dl_find_symbol($handle, "smq_$function") or fail("symbol missing");
DynaLoader::dl_install_xsub("main::smq", $symbol);
main::smq();
exit 0;
