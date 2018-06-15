use strict;

package Finance::Quote::ADVFNCurrencies;

use LWP::UserAgent;
use HTML::TreeBuilder::XPath;
use Encode qw(encode);

use vars qw/$VERSION $ADVFN_URL/;

$VERSION = '0.1';
$ADVFN_URL = 'https://br.advfn.com/common/search/exchanges/historical';

sub methods { return ( advfncurrencies => \&advfncurrencies ); }

{
  my @labels = qw/name last high low date isodate time volume price p_change
                  currency method exchange/;
  sub labels { return ( advfncurrencies => \@labels ); }
}

sub find_tables {
  my $tree = shift;
  my $path = shift;
  my $tables = shift;
  my $pos = shift;

  for my $node ($tree->findnodes($path)) {
    print $node->tag . "\n";
    my $n_class = $node->attr('class');
    my %classes;
    %classes = map { $_ => 1 } split(/ /, $n_class) if $n_class;

    if ($node->tag ne 'div' or not exists($classes{'TableElement'})) {
      my $n_title = $node->as_text();
      $$pos = @$tables if ($node->tag eq 'a' and $$pos < 0 and
                           $n_title =~ /Cota\xe7\xf5es Hist\xf3ricas/);
      next;
    }

    my @row;
    foreach my $col ($node->findnodes('.//tr[2]/td')) {
      push @row, $col->as_text();
    }
    push @$tables, \@row;
  }
}

sub advfncurrencies {
  my $quoter = shift;
  my @symbols = @_;
  return unless @symbols;
  my %info;

  my $ua = $quoter->user_agent;

  my %months = ('Jan' => '01', 'Fev' => '02', 'Mar' => '03', 'Abr' => '04',
                'Mai' => '05', 'Jun' => '06', 'Jul' => '07', 'Ago' => '08',
                'Set' => '09', 'Out' => '10', 'Nov' => '11', 'Dez' => '12');

  for my $symbol (@symbols) {
    my $req_1 = HTTP::Request->new(POST => $ADVFN_URL);
    $req_1->header('Accept' => '*/*');
    $req_1->header('User-Agent' => 'Perl');
    $req_1->header('Content-Type' => 'application/x-www-form-urlencoded');

    $req_1->content("symbol_ok=OK&symbol=FX:${symbol}");
    my $resp_1 = $ua->request($req_1);
    my $resp_1_st = $resp_1->code;

    if ($resp_1_st < 300 or $resp_1_st >= 400) {
      $info{$symbol, 'success'} = 0;
      $info{$symbol, 'errormsg'} = 'Unexpected response code while looking ' .
        'for symbol ' . ${symbol} . ': ' . $resp_1_st;
      next;
    }

    my $req_2 = HTTP::Request->new(GET => $resp_1->header('Location'));
    $req_2->header('User-Agent' => 'Perl');

    my $resp_2 = $ua->request($req_2);
    my $resp_2_st = $resp_2->code;

    if ($resp_2_st < 200 or $resp_2_st >= 300) {
      $info{$symbol, 'success'} = 0;
      $info{$symbol, 'errormsg'} = 'Unexpected response code while fetching ' .
        'historical data for symbol ' . ${symbol} . ': ' . $resp_2_st;
      next;
    }

    my $message = $resp_2->decoded_content;
    my $tree = HTML::TreeBuilder::XPath->new_from_content($message);
    my @tables;
    my $h_pos = -1;

    find_tables($tree, '/html/body//div[@id="quote_top"]/*',
                \@tables, \$h_pos);
    find_tables($tree, '/html/body//div[@id="content"]/*',
                \@tables, \$h_pos);

    if ($h_pos < 0 or @tables < $h_pos + 1 or @{$tables[0]} < 3 or
        @{$tables[$h_pos]} < 7) {
      $info{$symbol, 'success'} = 0;
      $info{$symbol, 'errormsg'} = 'Cannot find historical data for symbol ' .
        ${symbol};
      next;
    }

    my $date = $tables[$h_pos][0];
    $date =~ /(\w+)\W+(\w+)\W+(\w+)/;
    $date = "$1/" . $months{$2} . "/$3";

    $info{$symbol, 'name'} = encode('utf-8', $tables[0][0]);
    $info{$symbol, 'last'} = $tables[$h_pos][1];
    $info{$symbol, 'high'} = $tables[$h_pos][5];
    $info{$symbol, 'low'}  = $tables[$h_pos][4];
    $quoter->store_date(\%info, $symbol, {eurodate => $date});
    $info{$symbol, 'time'}  = '18:00:00';
    $info{$symbol, 'p_change'}  = $tables[$h_pos][3];
    $info{$symbol, 'volume'}  = $tables[$h_pos][6];

    foreach my $label (qw/last high low p_change volume/) {
      my $v = $info{$symbol, $label};
      $v =~ s/\.|\+|%//g;
      $v =~ s/,/./;
      $info{$symbol, $label} = $v;
    }

    # ensure float numbers are rounded to 4 decimal positions
    foreach my $label (qw/last high low p_change/) {
      $info{$symbol, $label} = sprintf '%.4f', $info{$symbol, $label};
    }

    $info{$symbol, 'currency'}  = 'BRL';
    $info{$symbol, 'method'}  = 'advfncurrencies';
    $info{$symbol, 'exchange'}  = $tables[0][2];
    $info{$symbol, 'price'} = $info{$symbol, 'last'};
    $info{$symbol, 'success'}  = 1;
  }

  return %info if wantarray;
  return \%info;
}
