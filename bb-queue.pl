#!/usr/bin/perl -w

#
# Print some simple queue statistics
#

use strict;
use warnings;
use diagnostics;

use HTTP::Date;
use Getopt::Long;
use Data::Dumper;

my $verbose = 0;

sub dprint($) {
    print shift if $verbose;
}

sub usage(@) {

    if ( defined $1 ) {
        print "Error: $1\n\n";
    }
    die "usage: $0 -i <interval> -q <queue> -p <pagination> [options]\n" . "\n"
      . "Parses postqueue output printing some statistics\n" . "\n"
      . "options:\n"
      . " -i : interval between two checks\n"
      . " -p : print header every p lines\n"
      . " -q : check only a given queue\n"
      . " -h : this help\n"
      . " -t : test parser\n"
      . " -v : a bit of debugging output\n"

      . "\n";

}

my $postqueue = "/usr/sbin/postqueue";

# Results
my %count_template = (
    'total'  => 0,
    'active' => 0,
    'hold'   => 0,

    'size'  => 0,
    'first' => time(),
    'last'  => time(),

    'wait_time'  => 0,
    'usage_time' => 0,
    'thruput'    => 0,
    'domains'    => { 'localhost' => 0 }

);

# Some regular expressions
my $re_queue_type = qq|[*!]|;
my $re_qid        = qq|[A-Z0-9]+|;
my $re_size       = qq|[0-9]+|;
my $re_from       = qq|[^ ]+|;
my $re_date       = qq|\\w{3}\\s+\\w{3}\\s+\\d+\\s+\\d+:\\d+:\\d+|;
my $re_postqueue =
  qq|($re_qid)($re_queue_type?)\\s+($re_size)\\s+($re_date)\\s+($re_from)|;

#
# parser function
#
sub parser($) {    #file handle
    my $que   = shift;
    my %count = %count_template;
    $count_template{'first'} = time();
    $count_template{'last'}  = time();

    print Dumper(%count) if ($verbose);
    while (<$que>) {
        chomp;
        if ( $_ =~ m/$re_postqueue/ ) {
            my ( $qid, $qtype, $size, $date, $from ) = ( $1, $2, $3, $4, $5 );
            $count{'total'}++ if defined $1;

            next unless defined $2;

            # Get queue type
            $count{'active'}++ if ( $2 eq "*" );
            $count{'hold'}++   if ( $2 eq "!" );

            # get mail size
            $count{'size'} += $3 if defined $3;

            # get time
            my $t = str2time($4);
            $count{'first'} = ( $count{'first'} < $t ) ? $count{'first'} : $t;
            $count{'last'}  = ( $count{'last'} > $t )  ? $count{'last'}  : $t;

            # get domain stats
            if ( defined $from ) {
                $from =~ s/.*@//;
                $count{'domains'}{$from}++;
            }

        }
    }

    #
    # wait_time - time elapsed since which the queue is used
    # usage_time - time interval in which the queue received items
    #
    $count{'wait_time'}  = time() - $count{'first'};
    $count{'usage_time'} = $count{'last'} - $count{'first'};

    #
    # Little's Law: QueueLength = Thruput * WaitTime
    #  the same for the size
    #
    $count{'thruput'} =
      $count{'wait_time'} > 0 ? $count{'total'} / $count{'wait_time'} : 0;

    $count{'Bps_thruput'} =
      $count{'wait_time'} > 0 ? $count{'size'} / $count{'wait_time'} : 0;

    return \%count;
}

sub main() {
    my ( $argc, @argv ) = ( $#ARGV, @ARGV );
    my $que;
    my $i = 0;
    my ( $help, $queue, $test );
    my ( $interval, $pagination, $domain ) = ( 5, 24, 0 );

    my $result = GetOptions(
        'i=s' => \$interval,     # server options
        'q=s' => \$queue,
        'p=s' => \$pagination,
        't'   => \$test,
        'v'   => \$verbose,
        'd'   => \$domain,

        'h|help' => \$help       # help verbose
    );

    test() if defined $test;

    usage() if ( $help or $argc < 1 );

    my $command = sprintf("$postqueue -p ");
    my %curr    = %count_template;
    my %prev;
    while (1) {
        open( $que, "$postqueue -p |" ) or die $!;
        my $h_curr = parser($que);
        %prev = %curr;
        %curr = %{$h_curr};

        my $speed =
          $prev{'total'} ? ( $curr{'total'} - $prev{'total'} ) / $interval : 0;

        my $usage =
          $curr{'wait_time'} ? $curr{'usage_time'} / $curr{'wait_time'} : 0;

        printf(
            "%-10s\t%10s\t%20s\t%20s\t%20s\t%5s\t%8s\n",
            'total',   'active', 'size', 'delta',
            'thruput', 'usage',  'Bps_thruput'
        ) if ( !( $i++ % $pagination ) );

        printf( "%-10d\t%10d\t%20d\t%20d\t%18.2f\t%3.2f\t%8d\n",
            $curr{'total'}, $curr{'active'}, $curr{'size'}, $curr{'wait_time'},
            $curr{'thruput'}, $usage, $curr{'Bps_thruput'}, );

        # from qSummary.pl
        if ($domain) {
            my %domains = %{ $curr{'domains'} };
            foreach my $key (
                reverse sort { $domains{$a} <=> $domains{$b} }
                keys %domains
              )
            {
                print "\t\t$key\t$domains{$key}\n";
            }
        }
        sleep($interval);
    }

}

#
# Tests
#
sub test() {

    sub test_hash_1() {
        my %domains = %{ $count_template{'domains'} };

        my @keys = keys %domains;
        die("domains") if ( not @keys );

        foreach my $k (@keys) {
            print "k: $k, " . $domains{$k} . "\n";
        }

    }

    sub test_re_1() {
        my $t_postqueue = <<END
4908384CA2*     240 Tue Jul 10 19:10:21  rpolli\@babel.it
                                         fabio\@ast.it
                                         gnarwl\@localhost.localdomain

CF88B84C92*     240 Tue Jul 10 19:10:20  rpolli\@babel.it
                                         fabio\@ast.it

1910B84C9B*     240 Tue Jul 10 19:10:21  rpolli\@babel.it
                                         fabio\@ast.it
                                         gnarwl\@localhost.localdomain
END
          ;
        my $t_postqueue_1 =
          '4908384CA2*     240 Tue Jul 10 19:10:21  rpolli@babel.it';
        my $t_postqueue_2 =
          '4908384CA2!     240 Tue Jul 10 19:10:21  rpolli@babel.it';
        my $x_from = 'rpolli@babel.it';
        my $x_date = "Tue Jul 10 19:10:21";
        my $x_qid  = "4908384CA2";
        {
            $t_postqueue_1 =~ $re_postqueue;

            my ( $qid, $qtype, $size, $date, $from ) = ( $1, $2, $3, $4, $5 );
            die("mismatched qid")           unless ( $qid   eq $x_qid );
            die("mismatched qtype")         unless ( $qtype eq "*" );
            die("mismatched from: [$from]") unless ( $from  eq $x_from );

            die("mismatched size") unless ( $size == 240 );
            die("mismatched date") unless ( $date eq $x_date );
        }

        {
            $t_postqueue_2 =~ m/$re_postqueue/;

            my ( $qid, $qtype, $size, $date, $from ) = ( $1, $2, $3, $4, $5 );
            die("mismatched qid")           unless ( $qid  eq $x_qid );
            die("mismatched from: [$from]") unless ( $from eq $x_from );

            die("mismatched qtype") unless ( $qtype eq "!" );
            die("mismatched size")  unless ( $size == 240 );
            die("mismatched date")  unless ( $date  eq $x_date );
        }
        return;

    }
    print "Tests\n";
    test_re_1;
    test_hash_1;

    exit 0;

}

#
# Main
#
&main;

