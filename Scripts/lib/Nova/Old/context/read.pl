use warnings;
use strict;

sub setFieldType {
	my ($res, $field, $type) = @_;
	my $order = $res->{_priv}{order};
	my ($idx) = grep { $order->[$_] eq $field } (0..$#$order);
	$res->{_priv}{types}[$idx] = $type;
}

my %handlers; # predeclare
%handlers = (
	'str#' => sub {
		my ($vals, $types, $titles) = @_;
		my @t = @$titles;
		my @ty;
		my %res;
		$res{pop @t} = pop @$vals; # end of record
		while (scalar(@t) > 1) {
			$res{shift @t} = shift @$vals;
			push @ty, shift @$types;
		}
		$res{$t[0]} = $vals;
		@ty = (@ty, 'list', $types->[-1]);
		$res{_priv} = { types => \@ty, order => $titles };
		return %res;
	},
	default => sub {
		my ($vals, $types, $titles) = @_;

		# Remove EOR
		my @order = @$titles;
		pop @order;

		my %res = (_priv => { types => [], order => \@order });
		for my $k (@order) {
			$res{$k} = shift @$vals;
			push @{$res{_priv}{types}}, shift @$types;
		}
		return %res;
	},
	outf => sub {
		my %outfhex = map { $_ => 1 } (17, 30, 43);
		my %res = $handlers{default}->(@_);
		my @ktypes = grep /^ModType/, keys %res;
		@ktypes = grep { $outfhex{$res{ModType}} } @ktypes;
		for my $k (@ktypes) {
			(my $v = $k) =~ s/ModType/ModVal/;
			setFieldType(\%res, $v, 'hex4');
		}
		return %res;
	},
	syst => sub {
		# Silly ConText spelling bug
		my ($vals, $types, $titles) = @_;
		map { s/^Visiblility$/Visibility/ } @$titles;
		return $handlers{default}->(@_);
	},
	weap => sub {
		my %res = $handlers{default}->(@_);
		setFieldType(\%res, 'Seeker', 'hex4');
		return %res;
	},
);

sub parseData {
	my ($data) = @_;
	my ($type, $ret);

	if ($data =~ /^"(.*)"$/) {
		my $str = $1;
		$str =~ s/\\q/\"/g;
		$str =~ s/\\r/\n/g;
		($type, $ret) = (string => $str);
	} elsif ($data =~ /^(#)(.*)$/ || $data =~ /^(0x)(.*)$/) {
		($type, $ret) = ($1 eq '#' ? 'color' : ('hex' . length($2)), hex($2));
	} else {
		($type, $ret) = ('misc', $data);
	}
}

sub parseLine {
	my ($line) = @_;
	chomp $line;
	my @vals = split /\t/, $line;
	my @types;

	my $idx = 0;
	for my $v (@vals) {
		($types[$idx++], $v) = parseData($v);
	}
	return (\@vals, \@types);
}

sub readType {
	my ($fh, $type) = @_;
	my (%ret, $titles);
	my $handler = $handlers{$type};
	$handler = $handlers{default} unless defined $handler;

	($titles) = parseLine(scalar(<$fh>));

	while (my $line = readLineSafe($fh)) {
		$line =~ /^(\S*)/;
		my $begin = deaccent($1);
		if ($begin eq $type) {
			my ($vals, $types) = parseLine($line);
			my %res = $handler->($vals, $types, $titles);
			$ret{$res{ID}} = \%res;
		} else {
			last;
		}
	}

	return \%ret;
}

sub readContext {
	my ($file, @types) = @_;
	my %wantType = map { deaccent($_) => 1 } @types;

	my $txt = openFindEncoding($file) or die "Can't open ConText: '$file': $!\n";
	my %ret;
	while (%wantType && (my $line = readLineSafe($txt))) {
		next unless $line =~ /^..Begin (\S+)/;
		my $type = deaccent($1);
		next unless $wantType{$type};

		$ret{$type} = readType($txt, $type);
		delete $wantType{$type};
	}
	close $txt;
	return \%ret;
}

1;
