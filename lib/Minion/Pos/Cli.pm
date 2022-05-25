package Minion::Pos::Cli;

use parent qw(Minion::System::ProcessFuture);
use strict;
use warnings;

use Carp qw(confess);
use File::Temp qw(tempfile);
use JSON;

use Minion::Io::Util qw(output_function);
use Minion::System::Process;
use Minion::System::ProcessFuture;

sub _init
{
    my ($self, $routine, %opts) = @_;
    my (%sopts, $value, $opt);

    confess() if (!defined($routine));
    confess() if (!grep { ref($routine) eq $_ } qw(CODE ARRAY));

    # $sopts{MAPOUT} = sub { return decode_json(shift()); };

    foreach $opt (qw(STDIN STDERR MAPOUT)) {
	if (defined($value = $opts{$opt})) {
	    $sopts{$opt} = $value;
	    delete($opts{$opt});
	}
    }

    return $self->SUPER::_init($routine, %sopts);
}

sub __pos_base_command
{
    return ('pos', '--no-color');
}

sub __format_cmd
{
    my ($cmd, @paths) = @_;
    my ($msg, $path, $fh, $line);

    $msg = join(' ', @$cmd) . "\n";

    foreach $path (@paths) {
	if (!open($fh, '<', $path)) {
	    $msg .= '  ' . $path . ": $!\n";
	} else {
	    $msg .= '  ' . $path . ":\n";

	    while (defined($line = <$fh>)) {
		chomp($line);
		$msg .= '    ' . $line . "\n";
	    }

	    close($fh);
	}
    }

    return $msg;
}

sub allocations_free
{
    my ($class, $allocation, %opts) = @_;
    my (%copts, @command, $value, $logger);

    confess() if (!defined($allocation));
    # confess() if (ref($ids) ne 'ARRAY');
    # confess() if (grep { ! m/^sfr(?:-[0-9a-f]+)+$/ } @$ids);

    $logger = sub {};

    @command = (
	__pos_base_command(), 'allocations', 'free'
	);

    if (defined($value = $opts{KEEP})) {
	push(@command, '--keep-calendar-event');
	delete($opts{KEEP});
    }

    if (defined($value = $opts{ERR})) {
	$copts{STDERR} = $value;
	delete($opts{ERR});
    }

    if (defined($value = $opts{LOG})) {
	$logger = output_function($value);
	delete($opts{LOG});
    }

    push(@command, $allocation);

    confess(join(' ', keys(%opts))) if (%opts);

    $logger->(__format_cmd(\@command));

    return $class->new(\@command, %copts);
}



sub nodes_reset
{
    my ($class, $node, %opts) = @_;
    my (%copts, @command, $value, $logger);

    confess() if (!defined($node));

    $logger = sub {};

    @command = (
	__pos_base_command(), 'nodes', 'reset',
	$node
	);

    if (defined($value = $opts{ERR})) {
	$copts{STDERR} = $value;
	delete($opts{ERR});
    }

    if (defined($value = $opts{LOG})) {
	$logger = output_function($value);
	delete($opts{LOG});
    }

    confess(join(' ', keys(%opts))) if (%opts);

    $logger->(__format_cmd(\@command));

    return $class->new(\@command, %copts);
}

sub nodes_bootstrap
{
    my ($class, $node, %opts) = @_;
    my (%copts, @command, $value, $logger);

    confess() if (!defined($node));

    $logger = sub {};

    @command = (
	__pos_base_command(), 'nodes', 'bootstrap',
	$node
	);

    if (defined($value = $opts{ERR})) {
	$copts{STDERR} = $value;
	delete($opts{ERR});
    }

    if (defined($value = $opts{LOG})) {
	$logger = output_function($value);
	delete($opts{LOG});
    }

    confess(join(' ', keys(%opts))) if (%opts);

    $logger->(__format_cmd(\@command));

    return $class->new(\@command, %copts);
}

sub nodes_stop
{
    my ($class, $node, %opts) = @_;
    my (%copts, @command, $value, $logger);

    confess() if (!defined($node));

    $logger = sub {};

    @command = (
	__pos_base_command(), 'nodes', 'stop',
	$node
	);

    if (defined($value = $opts{ERR})) {
	$copts{STDERR} = $value;
	delete($opts{ERR});
    }

    if (defined($value = $opts{LOG})) {
	$logger = output_function($value);
	delete($opts{LOG});
    }

    confess(join(' ', keys(%opts))) if (%opts);

    $logger->(__format_cmd(\@command));

    return $class->new(\@command, %copts);
}

sub nodes_update_status
{
    my ($class, $node, %opts) = @_;
    my (%copts, @command, $value, $logger);

    confess() if (!defined($node));

    $logger = sub {};

    @command = (
	__pos_base_command(), 'nodes', 'update_status',
	$node
	);

    if (defined($value = $opts{ERR})) {
	$copts{STDERR} = $value;
	delete($opts{ERR});
    }

    if (defined($value = $opts{LOG})) {
	$logger = output_function($value);
	delete($opts{LOG});
    }

    confess(join(' ', keys(%opts))) if (%opts);

    $logger->(__format_cmd(\@command));

    return $class->new(\@command, %copts);
}

sub commands_launch
{
    my ($class, $node, $cmd, %opts) = @_;
    my (%copts, @command, $value, $logger);

    confess() if (!defined($node));
    confess() if (!defined($cmd));
    confess() if (ref($cmd) ne 'ARRAY');
    confess() if (grep { ref($_) ne '' } @$cmd);

    $logger = sub {};

    @command = (
	__pos_base_command(), 'commands', 'launch', '--verbose', $node, '--',
	@$cmd
	);

    if (defined($value = $opts{ERR})) {
	$copts{STDERR} = $value;
	delete($opts{ERR});
    }

    if (defined($value = $opts{LOG})) {
	$logger = output_function($value);
	delete($opts{LOG});
    }

    confess(join(' ', keys(%opts))) if (%opts);

    $logger->(__format_cmd(\@command));

    return $class->new(\@command, %copts);
}

sub allocations_allocate
{
    my ($class, %opts) = @_;
    my (%copts, @command, $value, $logger, @nodes);

    $value = $opts{NODES};
    @nodes = @$value;
	delete($opts{NODES});
    confess() if (scalar(@nodes) == 0);

    $logger = sub {};

    @command = (
	__pos_base_command(), 'allocations', 'allocate'
	);

    if (defined($value = $opts{ERR})) {
	$copts{STDERR} = $value;
	delete($opts{ERR});
    }

    if (defined($value = $opts{LOG})) {
	$logger = output_function($value);
	delete($opts{LOG});
    }

    if (defined($value = $opts{DURATION})) {
	confess() if ($value !~ /^-?\d+$/);
	return if ($value <= 0);
	push(@command, '--duration', $value);
	delete($opts{DURATION});
    }

    push(@command, @nodes);

    confess(join(' ', keys(%opts))) if (%opts);

    $logger->(__format_cmd(\@command));

    return $class->new(\@command, %copts);
}

1;
__END__
