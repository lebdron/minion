package Minion::Pos::Allocation;

use parent qw(Minion::Fleet);
use strict;
use warnings;

use Carp qw(confess);
use Scalar::Util qw(blessed);
use Time::Local;

use Minion::Pos::Cli;
# use Minion::Aws::Event;
# use Minion::Aws::Image;
use Minion::Pos::Node;
use Minion::Fleet;
use Minion::System::WrapperFuture;

sub _init
{
    my ($self, $id, %opts) = @_;
    my ($value, @nodes, $node, @anodes, $anode);

    confess() if (!defined($id));
    # confess() if ($id !~ /^sfr(?:-[0-9a-f]+)+$/);

    $self->{__PACKAGE__()}->{_id} = $id;
    # $self->{__PACKAGE__()}->{_cache} = {};

    if (defined($value = $opts{ERR})) {
	$self->{__PACKAGE__()}->{_err} = $value;
	delete($opts{ERR});
    }

    if (defined($value = $opts{LOG})) {
	$self->{__PACKAGE__()}->{_log} = $value;
	delete($opts{LOG});
    }

    if (defined($value = $opts{KEEP})) {
	$self->{__PACKAGE__()}->{_keep} = $value;
	delete($opts{KEEP});
    }

    $value = $opts{NODES};
    @nodes = @$value;
    foreach $node (@nodes) {
        $anode = Minion::Pos::Node->new(
            $node, $self->_lopts()
        );
	    push(@anodes, $anode);
	}
	delete($opts{NODES});
    $self->{__PACKAGE__()}->{_nodes} = \@anodes;

    confess(join(' ', keys(%opts))) if (%opts);

    return $self->SUPER::_init();
}


sub allocate
{
    my ($class, %opts) = @_;
    my (%copts, %nopts, %iopts, $opt, $allocation, $value, $logger_error, $cli, @nodes);

    $value = $opts{NODES};
    @nodes = @$value;
    printf("nodes %s\n", join(',', @nodes));

    foreach $opt (qw(DURATION)) {
        if (defined($value = $opts{$opt})) {
            $copts{$opt} = $value;
            delete($opts{$opt});
        }
    }

    foreach $opt (qw(ERR LOG NODES)) {
	if (defined($value = $opts{$opt})) {
	    $copts{$opt} = $value;
	    $nopts{$opt} = $value;
	    delete($opts{$opt});
	}
    }

    if (defined($value = $opts{KEEP})) {
        $nopts{KEEP} = $value;
        delete($opts{KEEP});
    }

    if (defined($value = $opts{ALLOCATION})) {
        $allocation = $value;
        delete($opts{ALLOCATION});
    }

    confess(join(' ', keys(%opts))) if (%opts);

    if (defined($allocation)) {
        return $class->new($allocation, %nopts);
    }

    $cli = Minion::Pos::Cli->allocations_allocate(%copts);

    return Minion::System::WrapperFuture->new($cli, MAPOUT => sub {
	my ($reply) = @_;
    my $id;
    if ($reply =~ m!([a-z]+_\d+_\d+_\d+)!) {
        $id = $1;
    } else {
        confess();
    }

	return $class->new($id, %nopts);
    });
}

sub free
{
    my ($self, @err) = @_;
    my (%copts, $id, $cli, $value);

    confess() if (@err);

    %copts = $self->_lopts();
    if (defined($value = $self->{__PACKAGE__()}->{_keep})) {
	$copts{KEEP} = $value;
    }

    $cli = Minion::Pos::Cli->allocations_free(
	$self->id(),
	%copts
	);

    return $cli;
}

sub id
{
    my ($self, @err) = @_;

    confess() if (@err);

    return $self->{__PACKAGE__()}->{_id};
}

sub _log
{
    my ($self) = @_;

    return $self->{__PACKAGE__()}->{_log};
}

sub _err
{
    my ($self) = @_;

    return $self->{__PACKAGE__()}->{_err};
}

sub _lopts
{
    my ($self) = @_;
    my (%lopts, $value);

    if (defined($value = $self->_err())) {
	$lopts{ERR} = $value;
    }

    if (defined($value = $self->_log())) {
	$lopts{LOG} = $value;
    }

    return %lopts;
}

sub nodes
{
    my ($self) = @_;
    my $nodes;

    $nodes = $self->{__PACKAGE__()}->{_nodes};

    return @$nodes;
}

1;
__END__
