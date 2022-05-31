package Minion::Pos::Node;

use parent qw(Minion::Ssh);
use strict;
use warnings;

use Carp qw(confess);

use Minion::Pos::Cli;
use Minion::Ssh;
use Minion::System::ProcessFuture;

sub _init
{
    my ($self, $instance_id, %opts) = @_;
    my (%sopts, $opt, $value);

    # confess() if ($instance_id !~ /^i-[0-9a-f]+$/);
    # confess() if (!__check_ip4($public_ip));
    # confess() if (!__check_ip4($private_ip));
    # confess() if ($fleet_id !~ /^sfr(?:-[0-9a-f]+)+$/);

    $self->{__PACKAGE__()}->{_cache} = {};

    if (defined($value = $opts{ERR})) {
	$sopts{ERR} = $value;
	$self->{__PACKAGE__()}->{_err} = $value;
	delete($opts{ERR});
    }

    if (defined($value = $opts{LOG})) {
	$sopts{LOG} = $value;
	$self->{__PACKAGE__()}->{_log} = $value;
	delete($opts{LOG});
    }

    # if (defined($value = $opts{REGION})) {
	# $self->{__PACKAGE__()}->{_region} = $value;
	# delete($opts{REGION});
    # } else {
	# $self->{__PACKAGE__()}->{_region} =
	#     Minion::Aws::Cli->get_region()->get();
    # }

    if (defined($value = $opts{USER})) {
	$sopts{USER} = $value;
	delete($opts{USER});
    }

    confess(join(' ', keys(%opts))) if (%opts);

    $self->{__PACKAGE__()}->{_instance_id} = $instance_id;
    $self->{__PACKAGE__()}->{_host} = $instance_id =~ m!^pc[0-9]\.[a-z]$! ? $instance_id . '.ilab' : $instance_id;
    $self->update();
    # $self->{__PACKAGE__()}->{_private_ip} = $private_ip;
    # $self->{__PACKAGE__()}->{_fleet_id} = $fleet_id;

    return $self->SUPER::_init(
        $self->host(),
	# ALIASES => {
	#     'aws:id'         => sub { return $self->id() },
	#     'aws:public-ip'  => sub { return $self->public_ip() },
	#     'aws:private-ip' => sub { return $self->private_ip() },
	#     'aws:region'     => sub { return $self->region() }
	# },
        %sopts);
}

sub reset
{
    my ($self, %opts) = @_;
    my (%copts, $value, $cli);

    confess(join(' ', keys(%opts))) if (%opts);

    if (defined($value = $self->{__PACKAGE__()}->{_err})) {
	$copts{ERR} = $value;
    }

    if (defined($value = $self->{__PACKAGE__()}->{_log})) {
	$copts{LOG} = $value;
    }

    $cli = Minion::Pos::Cli->nodes_reset($self->id(), %copts);

    return $cli;
}

sub bootstrap
{
    my ($self, %opts) = @_;
    my (%copts, $value, $cli);

    confess(join(' ', keys(%opts))) if (%opts);

    if (defined($value = $self->{__PACKAGE__()}->{_err})) {
	$copts{ERR} = $value;
    }

    if (defined($value = $self->{__PACKAGE__()}->{_log})) {
	$copts{LOG} = $value;
    }

    $cli = Minion::Pos::Cli->nodes_bootstrap($self->id(), %copts);

    return $cli;
}

sub stop
{
    my ($self, %opts) = @_;
    my (%copts, $value, $cli);

    confess(join(' ', keys(%opts))) if (%opts);

    if (defined($value = $self->{__PACKAGE__()}->{_err})) {
	$copts{ERR} = $value;
    }

    if (defined($value = $self->{__PACKAGE__()}->{_log})) {
	$copts{LOG} = $value;
    }

    $cli = Minion::Pos::Cli->nodes_stop($self->id(), %copts);

    return $cli;
}

sub update_status
{
    my ($self, %opts) = @_;
    my (%copts, $value, $cli);

    confess(join(' ', keys(%opts))) if (%opts);

    if (defined($value = $self->{__PACKAGE__()}->{_err})) {
	$copts{ERR} = $value;
    }

    if (defined($value = $self->{__PACKAGE__()}->{_log})) {
	$copts{LOG} = $value;
    }

    $cli = Minion::Pos::Cli->nodes_update_status($self->id(), %copts);

    return $cli;
}

sub launch
{
    my ($self, $cmd, %opts) = @_;
    my (%copts, $value, $cli);

    confess() if (!defined($cmd));
    confess() if (ref($cmd) ne 'ARRAY');
    confess() if (grep { ref($_) ne '' } @$cmd);

    confess(join(' ', keys(%opts))) if (%opts);

    if (defined($value = $self->{__PACKAGE__()}->{_err})) {
	$copts{ERR} = $value;
    }

    if (defined($value = $self->{__PACKAGE__()}->{_log})) {
	$copts{LOG} = $value;
    }

    $cli = Minion::Pos::Cli->commands_launch($self->id(), $cmd, %copts);

    return $cli;
}

sub id
{
    my ($self, @err) = @_;

    confess() if (@err);

    return $self->{__PACKAGE__()}->{_instance_id};
}

sub host
{
    my ($self, @err) = @_;

    confess() if (@err);

    return $self->{__PACKAGE__()}->{_host};
}

sub update
{
    my ($self, @err) = @_;

    my $iface = $self->id() =~ m!^pc[0-9]\.[a-z]$! ? 'eth-static' : 'eno1';
    my $ret = $self->launch([ 'ip', '-4', '-o', 'a', 'show', $iface ])->get();
    if ($ret =~ m!inet (.*)/!) {
        $self->{__PACKAGE__()}->{_cache}->{_private_ip} = $1;
    }
}

sub _get_cached
{
    my ($self, $name, @err) = @_;
    my ($ret);

    confess() if (@err);

    $ret = $self->{__PACKAGE__()}->{_cache}->{$name};

    if (!defined($ret)) {
	$self->update();
	$ret = $self->{__PACKAGE__()}->{_cache}->{$name};
    }

    return $ret;
}

sub private_ip
{
    my ($self, @args) = @_;

    return $self->_get_cached('_private_ip', @args);
}

sub public_ip
{
    my ($self, @err) = @_;

    confess() if (@err);

    return $self->private_ip();
}

sub region
{
    my ($self, @err) = @_;

    confess() if (@err);

    # return $self->{__PACKAGE__()}->{_region};
    return '00-0-0';
}


1;
__END__
