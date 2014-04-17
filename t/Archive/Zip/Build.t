use strict;
use warnings;

use Test::More tests => 3;
BEGIN { use_ok "Archive::Zip::Build" };

local $ENV{PATH}="/bin:/usr/bin";
open(my $test_out, "|-", "grep", "-q", ".");

my $mz = new_ok "Archive::Zip::Build" => [$test_out];
$mz->print_item(
 Name=>"foo/",
 Time=>time,
 ExtAttr=>0755<<16,
 exTime => [time, time, time],
 Method => "store",
 ExtraFieldLocal=>[],
);
$mz->print_item(
 Name=>"foo/bar",
 Time=>time,
 ExtAttr=>0755<<16,
 exTime => [time, time, time],
 Method => "deflate",
 ExtraFieldLocal=>[],
 content => "test",
);
ok($mz->close, "zip: some output provided");

done_testing();
