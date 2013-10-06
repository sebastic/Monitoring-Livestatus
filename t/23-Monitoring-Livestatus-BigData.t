#!/usr/bin/env perl

#########################

use strict;
use Test::More tests => 14;
BEGIN { use_ok('Monitoring::Livestatus') };

my $testport    = 60123;
my $testresults = $ARGV[0] || 5;

#########################
# create object with single arg
my $ml = Monitoring::Livestatus->new('localhost:'.$testport);
isa_ok($ml, 'Monitoring::Livestatus', 'Monitoring::Livestatus->new()');

#########################
# prepare testfile
my $testfile   = '/tmp/testresult.json';
open(my $fh, '>', $testfile.'.data') or die($testfile.'.data: '.$!);
print $fh "[";
for my $x (1..$testresults) {
    printf($fh '["Test Host %d","some test pluginoutput............................................",1],%s', $x, "\n");
}
print $fh "]\n";
close($fh);
ok(-f $testfile, "testfile: ".$testfile.".data written");

chomp(my $size = `du -h $testfile.data`);
ok($size, $size);

chomp(my $bytes = `du -b $testfile.data | awk '{print \$1}'`);
ok($bytes, 'testfile has '.$bytes.' bytes');

open($fh, '>', $testfile.'.head') or die($testfile.'.head: '.$!);
printf($fh "200 %12d\n", $bytes);
close($fh);
`cat $testfile.head $testfile.data > $testfile`;
unlink($testfile.'.head', $testfile.'.data');

##########################################################
my $mem_start = get_memory_usage();
ok($mem_start, sprintf('memory at start: %.2f MB', $mem_start));

##########################################################
# start netcat
`netcat -vvv -w 3 -l -p $testport >/tmp/blah 2>&1 < $testfile &`;
sleep(0.1);
ok(1, "netcat started");

##########################################################
my $result = $ml->selectall_arrayref(
      "GET hosts\nColumns: name plugin_output status", {
        Slice => {},
      }
    );
is(ref $result, 'ARRAY', 'result is an array');
is(scalar @{$result}, $testresults, 'result has right number');
is(ref $result->[$testresults-1], 'HASH', 'result contains hashes');
is($result->[$testresults-1]->{'name'}, 'Test Host '.$testresults, 'result contains all hosts');


##########################################################
my $mem_end = get_memory_usage();
ok($mem_end, sprintf('memory at end: %.2f MB', $mem_end));
my $delta = $mem_end - $mem_start;
ok($delta, sprintf('memory delta: %.2f MB', $delta));
ok($delta, sprintf('memory per entry: %.6f MB', $delta/$testresults));

##########################################################
sub get_memory_usage {
    my($pid) = @_;
    $pid = $$ unless defined $pid;

    my $rsize;
    open(my $ph, '-|', "ps -p $pid -o rss") or die("ps failed: $!");
    while(my $line = <$ph>) {
        if($line =~ m/(\d+)/mx) {
            $rsize = sprintf("%.2f", $1/1024);
        }
    }
    CORE::close($ph);
    return($rsize);
}
