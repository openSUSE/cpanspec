package CPAN2OBS;
use strict;
use warnings;
use 5.010;

use base 'Exporter';
our @EXPORT_OK = qw/ debug info prompt /;

use Data::Dumper;
use Term::ANSIColor qw/ colored /;
use YAML::XS qw/ DumpFile /;
use XML::Simple qw/ XMLin /;
use Storable qw/ retrieve store /;
use File::Basename qw/ basename /;
use File::Copy qw/ copy move /;
use File::Path qw/ remove_tree /;
use File::Spec;
use Parse::CPAN::Packages;
use File::Glob qw/ bsd_glob /;
use FindBin '$Bin';

use Moo;
use namespace::clean;

has data => ( is => 'rw', coerce => \&_coerce_data );
has cpandetails => ( is => 'ro' );
has skip => ( is => 'ro' );
has apiurl => ( is => 'ro' );
has cpanmirror => ( is => 'ro' );
has cpanspec => ( is => 'ro' );
has project_prefix => ( is => 'ro', coerce => \&_coerce_project_prefix );
has locked => ( is => 'rw' );

sub _coerce_data {
    my ($data) = @_;
    unless (File::Spec->file_name_is_absolute($data)) {
        $data = File::Spec->rel2abs($data);
    }
    return $data;
}

sub _coerce_project_prefix {
    my ($prefix) = @_;
    unless ($prefix =~ m/^[A-Za-z][A-Za-z:-]+\z/) {
        die "Invalid project prefix '$prefix'";
    }
    return $prefix;
}

sub debug {
    my ($msg) = @_;
    say STDERR colored([qw/ grey15 /], $msg);
}
sub info {
    my ($msg) = @_;
    say colored([qw/ magenta /], $msg);
}
sub prompt {
    my ($msg) = @_;
    print colored([qw/ cyan /], $msg);
    chomp(my $answer = <STDIN>);
    $answer = uc $answer;
    return $answer;
}

sub fetch_status {
    my ($self, $letter) = @_;
    my $data = $self->data;
    my $status_file = "$data/status/$letter.tsv";
    my %states;
    unless (-e $status_file) {
        return \%states;
    }
    $self->lockdata;
    open my $fh, '<', $status_file or die $!;
    while (my $line = <$fh>) {
        chomp $line;
        my ($dist, $status, $version, $url, $obs_tar, $obs_ok) = split /\t/, $line;
        $states{ $dist } = [ $status, $version, $url, $obs_tar, $obs_ok ];
    }
    close $fh;
    $self->unlockdata;
    return \%states;
}

sub fetch_status_perl {
    my ($self, $letter) = @_;
    my $data = $self->data;
    my $status_file = "$data/status/perl.tsv";
    my %states;
    unless (-e $status_file) {
        return \%states;
    }
    $self->lockdata;
    open my $fh, '<', $status_file or die $!;
    while (my $line = <$fh>) {
        chomp $line;
        my ($dist, $status, $version, $url, $obs_version) = split /\t/, $line;
        $states{ $dist } = [ $status, $version, $url, $obs_version ];
    }
    close $fh;
    $self->unlockdata;
    return \%states;
}

sub write_status {
    my ($self, $letter, $states) = @_;
    my $data = $self->data;
    mkdir "$data/status";
    my $status_file = "$data/status/$letter.tsv";
    open my $fh, '>', $status_file or die $!;
    for my $dist (sort keys %$states) {
        my $status = $states->{ $dist };
        say $fh join "\t", $dist, @$status;
    }
    close $fh;
}

sub fetch_cpan_list {
    my ($self) = @_;
    $self->lockdata;
    my $data = $self->data;
    my $cpan_modules_dir = "$data/cpan";
    my $cpan_stats = "$cpan_modules_dir/stats.yaml";
    my $details = "$data/02packages.details.txt.gz";
    my $details_url = $self->cpandetails;

    my $details_mtime = -e $details ? (stat $details)[9] : 0;
    my $stats_mtime = -e $cpan_stats ? (stat $cpan_stats)[9] : 0;
    if ($details_mtime + 60 * 30 < time) {
        my $cmd = "wget -q $details_url -O $details";
        debug("CMD $cmd");
        system $cmd;
        $details_mtime = -e $details ? (stat $details)[9] : 0;
    }
    else {
        info("$details uptodate");
    }
    if ($stats_mtime >= $details_mtime) {
        info("$cpan_stats uptodate");
        $self->unlockdata;
        return;
    }
    info("Parsing $details");
    my $p = Parse::CPAN::Packages->new($details);
    my %seen;
    my %upstream;
    for my $m ($p->packages) {
        $m = $m->distribution;
        my $url = $m->prefix;
        my $dist = $m->dist;
        unless ($dist) {
            next;
        }
        if ($self->skip->{ $dist }) {
            info("Ignoring $dist");
            next;
        }
        my $version = $m->version;
        if (not $version) {
            #warn sprintf "Distribution %s has no version defined", $url;
            next;
        }
        my $first = uc substr $dist, 0, 1;
        if ($dist eq 'XML-Xerces') {
            # versions like '2.7.0-1' are not parseable.
            # XML-Xerces is in the module index multiple times with different
            # versions and that leads to a different version almost every day
            $version =~ s/-//g;
        }
        my $v = eval { version->parse($version); };
        $v ||= version->declare('0');
        if (not exists $seen{ $dist } or ($seen{ $dist } ) < $v) {
            $seen{ $dist } = $v;
            $upstream{ $first }->{ $dist } = [$v, $url];
        }
    }

    my %stats;
    my $total = 0;
    for my $letter ('A' .. 'Z') {
        my $count = keys %{ $upstream{ $letter } };
        $total += $count;
        $stats{ $letter } = $count;
        $self->hash_to_cpan_file($letter, $upstream{ $letter });
    }
    $stats{total} = $total;
    DumpFile($cpan_stats, \%stats);

    system "cat $cpan_stats";
    $self->unlockdata;
}

sub hash_to_cpan_file {
    my ($self, $letter, $upstream) = @_;
    my $data = $self->data;
    my $cpan_modules_dir = "$data/cpan";
    mkdir $cpan_modules_dir;
    my $cpan_modules_file = "$cpan_modules_dir/$letter.tsv";

    open my $fh, '>', $cpan_modules_file or die $!;
    for my $dist (sort keys %$upstream) {
        my $info = $upstream->{ $dist };
        my ($version, $url) = @$info;
        say $fh join "\t", ($dist, $version, $url);
    }
    close $fh;
}

sub from_cpan_file {
    my ($self, $letter) = @_;
    my $data = $self->data;
    my $cpan_modules_dir = "$data/cpan";
    mkdir $cpan_modules_dir;
    my $cpan_modules_file = "$cpan_modules_dir/$letter.tsv";

    open my $fh, '<', $cpan_modules_file or die $!;
    my %upstream;
    while (my $line = <$fh>) {
        chomp $line;
        my ($dist, $version, $url) = split m/\t/, $line;
        $upstream{ $dist} = [ $version, $url ];
    }
    close $fh;
    return \%upstream;
}

sub fetch_obs_info {
    my ($self, $letter) = @_;
    my $data = $self->data;
    my $apiurl = $self->apiurl;
    my $project_prefix = $self->project_prefix . $letter;

    my $cache = $self->fetch_obs_cache($letter);

    my $obsdir = "$data/obs";
    my $letter_xml = "$obsdir/CPAN-$letter.xml";
    mkdir $obsdir;
    my %obs_info;

    my $old =(not -e $letter_xml or ((stat $letter_xml)[9] + 60 * 60) < time);
    if (1) {
        my $cmd = "osc -A $apiurl api '/source/$project_prefix?view=info' >$letter_xml";
        debug("CMD $cmd");
        system $cmd;
    }
    if (not -s $letter_xml) {
        return \%obs_info;
    }
    my $info = XMLin($letter_xml)->{sourceinfo};
    return \%obs_info unless $info;
    $info = [$info] unless ref $info eq 'ARRAY';

    mkdir "$data/project-xml";
    for my $pi (@$info) {
        my $srcmd5 = $pi->{srcmd5};
        my $package = $pi->{package};
        my $cached = $cache->{ $srcmd5 };
        if (not defined $cached) {
            info("fetch obs xml for $package");
            my $cmd = sprintf "osc -A %s api /source/%s/%s >$data/project-xml/$package.xml",
                $apiurl, $project_prefix, $package;
            debug("CMD $cmd");
            system $cmd;

            unless (-s "$data/project-xml/$package.xml") {
                warn __PACKAGE__.':'.__LINE__.": !!!! no osc data for $package\n";
                next;
            }
            my $pxml = XMLin "$data/project-xml/$package.xml";
            my $name = $pxml->{name};
            $obs_info{ $name }->{ok} = 1;
            if ($pxml->{entry}->{'cpanspec.error'}) {
                $obs_info{ $name }->{ok} = 0;
            }
            for my $entry (keys %{ $pxml->{entry} }) {
                if ($entry =~ m/\.tar/ || $entry =~ m/\.tgz$/ || $entry =~ m/\.zip$/) {
                    $obs_info{ $name }->{archive} = $entry;
                }
            }
            $cache->{ $srcmd5 } = $obs_info{ $package } || {};
            $self->store_obs_cache($letter, $cache);
        }
        else {
            if (ref $cached) {
                $obs_info{ $package } = $cached;
            }
            else {
                $obs_info{ $package } = { archive => $cached, ok => 1 };
            }
        }
    }
    return \%obs_info;
}

sub fetch_obs_cache {
    my ($self, $letter) = @_;
    my $data = $self->data;
    mkdir "$data/obs-cache";
    my $cachefile = "$data/obs-cache/$letter";
    my $cache = {};
    eval { $cache = retrieve($cachefile); };
    return $cache;
}

sub store_obs_cache {
    my ($self, $letter, $cache) = @_;
    my $data = $self->data;
    mkdir "$data/obs-cache";
    my $cachefile = "$data/obs-cache/$letter";
    store $cache, $cachefile;
}

sub create_package_xml {
    my ($self, $pkg, $spec) = @_;
    my $xmlfile = "tmp-package.xml";
    my $xml;

    if (-f $spec) {
        my $noarch;
        open my $fh, '<', $spec or die $!;
        while (<$fh>) {
            $noarch = 1 if m/^BuildArch.*noarch/;
        }
        close $fh;

        if ($noarch) {
            $xml = <<"EOM";
<package name='$pkg'><title/><description/><build><disable arch='i586'/></build></package>
EOM
        }
        else {
            $xml = <<"EOM";
<package name='$pkg'><title/><description/></package>
EOM
        }
    }
    else {
        $xml = "<package name='$pkg'><title/><description/><build><disable/></build></package>\n";
    }
    {
        open my $fh, '>', $xmlfile or die $!;
        print $fh $xml;
        close $fh;
    }
    return $xmlfile;
}

sub update_obs {
    my ($self, $letter, $args) = @_;
    my $packages = $args->{packages};
    $self->lockdata;
    my $data = $self->data;

    my $osc = "$data/osc";
    my $dir = "$osc/$letter";
    # removing previous osc checkouts
    remove_tree $dir, { verbose => 0, safe => 1 };

    my $states = $self->fetch_status($letter);
    my @keys = sort keys %$states;
    if ($packages and @$packages) {
        info("Requested (@$packages)");
        @keys = @$packages;
    }

    my $max = $args->{max};
    my $counter = 0;
    for my $dist (@keys) {
        my $dist_status = $states->{ $dist };
        unless ($dist_status) {
            info("No status found for '$dist'");
            next;
        }
        my ($status, $version, $url) = @$dist_status;
        unless ($args->{redo}) {
            next if ($status eq 'done');
        }
        if ($status =~ m/^error/) {
            info("Skip $dist ($status)");
            next;
        }
        $counter++;
        last if $counter > $max;
        info("($counter) updating $dist (@$dist_status)");
        my $answer = 'Y';
        if ($args->{ask}) {
            $answer = prompt("Update $dist? [y/N/q] ") || 'N';
            last if $answer eq 'Q';
            next if $answer eq 'N';
            info("y/n/q") if $answer ne 'Y';
        }
        if ($answer eq 'Y') {
            eval {
                $self->osc_update_dist($letter, $dist, $dist_status, $args);
            };
            my $err = $@;
            if ($err) {
                debug("ERROR: $dist $err");
                $states->{ $dist }->[0] = 'error';
                info("updating states ($letter)");
                $self->write_status($letter, $states);
            }
        }
    }
    $self->unlockdata;
}

sub update_obs_perl {
    my ($self, $args) = @_;
    my $packages = $args->{packages};
    $self->lockdata;
    my $project_prefix = $self->project_prefix;
    my $data = $self->data;
    my $apiurl = $self->apiurl;

    my $auto_projects = "$data/auto.xml";
    my $cmd = sprintf "osc -A $apiurl api /source/%s > %s",
        $project_prefix, $auto_projects;
    debug("CMD $cmd");
    system $cmd;
    my $existing = XMLin($auto_projects)->{entry};

    my $osc = "$data/osc";
    my $dir = "$osc/perl";
    # removing previous osc checkouts
    remove_tree $dir, { verbose => 0, safe => 1 };

    my $states = $self->fetch_status_perl();
    my @keys = sort keys %$states;
    if ($packages and @$packages) {
        info("Requested (@$packages)");
        @keys = @$packages;
    }

    my $max = $args->{max};
    my $counter = 0;
    for my $dist (@keys) {
        my %args = %$args;
        my $dist_status = $states->{ $dist };
        unless ($dist_status) {
            info("No status found for '$dist'");
            next;
        }
        my ($status, $version, $url) = @$dist_status;
        unless ($args{redo}) {
            next if ($status eq 'done' or $status eq 'older');
        }
        if ($status =~ m/^error/) {
            info("Skip $dist ($status)");
            next;
        }

        my $pkg = "perl-$dist";
        if ($existing->{ $pkg }) {
            $args{exists} = 1;
            my $tar = basename $url;

            my $pxml = "/tmp/$pkg-autoupdate.xml";
            my $cmd = sprintf "osc -A $apiurl api /source/%s/%s >%s",
                $project_prefix, $pkg, $pxml;
            system $cmd and die "Error ($cmd): $?";
            my $info = XMLin($pxml);
            unlink $pxml;
            if ($info->{entry}->{ $tar }) {
                debug("$tar already exists, skipping");
                next;
            }
        }

        $counter++;
        last if $counter > $max;

        info("($counter) updating $dist (@$dist_status)");
        my $answer = 'Y';
        if ($args{ask}) {
            $answer = prompt("Update $dist? [y/N/q] ") || 'N';
            last if $answer eq 'Q';
            next if $answer eq 'N';
            info("y/n/q") if $answer ne 'Y';
        }
        if ($answer eq 'Y') {
            eval {
                $self->osc_update_dist_perl($dist, $dist_status, \%args);
            };
            my $err = $@;
            if ($err) {
                debug("ERROR: $dist $err");
                $states->{ $dist }->[0] = 'error';
                info("updating states (perl)");
                $self->write_status(perl => $states);
            }
        }
    }
    $self->unlockdata;
}

sub osc_update_dist {
    my ($self, $letter, $dist, $todo, $args) = @_;
    my $data = $self->data;
    my $apiurl = $self->apiurl;
    my $mirror = $self->cpanmirror;
    my $cpanspec = $self->cpanspec;
    my $project_prefix = $self->project_prefix . $letter;

    my $osc = "$data/osc";
    mkdir $osc;
    my $dir = "$osc/$letter";
    mkdir $dir;
    chdir $dir;
    debug("osc_update_dist($dist)");
    my ($status, $version, $url, $obs_tar, $obs_status) = @$todo;
    my $pkg = "perl-$dist";
    my $spec = "$pkg.spec";
    my $tar = basename $url;

    {
        my $cmd = "wget --tries 5 --timeout 30 --connect-timeout 30 -nc -q $mirror/authors/id/$url -O $tar -o /dev/null";
        debug("CMD $cmd");
        system $cmd;
        if ($? or not -f $tar) {
            info("Error fetching $url, skip ('$cmd': $?)");
            return 0;
        }
    }
    my $error = 1;
    {
        my $cmd = sprintf
            "timeout 180 perl $cpanspec -v -f --pkgdetails %s --skip-changes %s > cpanspec.error 2>&1",
            "$data/02packages.details.txt.gz", $tar;
        if (system $cmd or not -f $spec) {
            info("Error executing cpanspec");
        }
        else {
            $error = 0;
            unlink "cpanspec.error";
        }
    }
    my $xmlfile = $self->create_package_xml($pkg, $spec);
    my $project = "$project_prefix/$pkg";

    {
        my $cmd = sprintf "osc -A %s meta pkg %s %s -F %s",
            $apiurl, $project_prefix, $pkg, $xmlfile;
        debug("CMD $cmd");
        system $cmd
            and die "Error executing '$cmd': $?";
    }

    my $checkout = "$dir/$project_prefix/$pkg";
    if (-e $checkout) {
        debug("REMOVE $checkout");
        remove_tree $checkout, { verbose => 0, safe => 1 };
    }
    {
        my $cmd = sprintf "osc -A %s co %s/%s",
            $apiurl, $project_prefix, $pkg;
        system $cmd
            and die "Error executing '$cmd': $?";
    }
    chdir $checkout;
    if ($obs_tar) {
        my $cmd = "[[ -e $obs_tar ]] && rm $obs_tar || true";
        debug("CMD $cmd");
        system $cmd and die "Error executig '$cmd': $?";

    }
    {
        my $cmd = "[[ -e cpanspec.error ]] && rm cpanspec.error || true";
        debug("CMD $cmd");
        system $cmd and die "Error executig '$cmd': $?";

        $cmd = "[[ -e $spec ]] && rm $spec || true";
        debug("CMD $cmd");
        system $cmd and die "Error executig '$cmd': $?";
    }
    if ($error) {
        move "../../cpanspec.error", $checkout or die $!;
    }
    else {
        move "../../$spec", $checkout or die $!;
    }
    move "../../$tar", $checkout or die $!;
    {
        my $cmd = "osc addremove";
        debug("CMD $cmd");
        system $cmd and die "Error executig '$cmd': $?";
        if ($args->{ask_commit}) {
            my $answer = prompt("Commit? [Y/n]") || 'Y';
            if ($answer ne 'Y') {
                info("$pkg - no commit");
                return;
            }
        }

        $cmd = "osc ci -mupdate";
        debug("CMD $cmd");
        system $cmd and die "Error executig '$cmd': $?";
    }
    unlink "$dir/$xmlfile";
    return;
}

sub osc_update_dist_perl {
    my ($self, $dist, $todo, $args) = @_;
    my $exists = $args->{exists};
    my $data = $self->data;
    my $apiurl = $self->apiurl;
    my $mirror = $self->cpanmirror;
    my $cpanspec = $self->cpanspec;
    my $project_prefix = $self->project_prefix;
    my $letter = 'perl';

    my $osc = "$data/osc";
    mkdir $osc;
    my $dir = "$osc/$letter";
    mkdir $dir;
    chdir $dir;
    debug("osc_update_dist($dist)");
    my ($status, $version, $url, $obs_tar, $obs_status) = @$todo;
    my $pkg = "perl-$dist";
    my $spec = "$pkg.spec";
    my $tar = basename $url;

    if ($exists) {
        my $cmd = sprintf "osc -A $apiurl rdelete -mrecreate -f %s %s",
            $project_prefix, $pkg;
        debug("CMD $cmd");
        system $cmd and die "Error ($cmd): $?";
    }

    {
        my $cmd = sprintf "osc -A $apiurl branch devel:languages:perl %s %s",
            $pkg, $project_prefix;
        debug("CMD $cmd");
        system $cmd and die "Error ($cmd): $?";
    }
    {
        my $cmd = sprintf
            "wget --tries 5 --timeout 30 --connect-timeout 30 -nc -q %s -O $dir/$tar -o /dev/null",
            "$mirror/authors/id/$url";
        debug("CMD $cmd");
        system $cmd;
        if ($? or not -f "$dir/$tar") {
            info("Error fetching $url, skip ('$cmd': $?)");
            return 0;
        }
    }

    my $checkout = "$dir/$project_prefix/$pkg";
    if (-e $checkout) {
        debug("REMOVE $checkout");
        remove_tree $checkout, { verbose => 0, safe => 1 };
    }
    {
        my $cmd = sprintf "osc -A %s co %s/%s",
            $apiurl, $project_prefix, $pkg;
        system $cmd
            and die "Error executing '$cmd': $?";
    }
    chdir $checkout;

    my $old_tar = '';
    for my $tar (bsd_glob("{$dist-*.tar*,$dist-*.tgz,$dist-*.zip}")) {
        $old_tar = $tar;
        unlink $tar;
    }
    move "$dir/$tar", $checkout or die $!;
    my $error = 1;
    copy("$Bin/../cpanspec.yml", "$checkout/cpanspec.yml") unless -f "cpanspec.yml";
    {
        my $cmd = sprintf
            "timeout 180 perl $cpanspec -f --pkgdetails %s --old-file %s %s > cpanspec.error 2>&1",
            "$data/02packages.details.txt.gz", ".osc/$old_tar", $tar;
        debug("CMD $cmd");
        if (system $cmd or not -f $spec) {
            system("cat cpanspec.error");
            info("Error executing cpanspec");
        }
        else {
            system("cat cpanspec.error");
            $error = 0;
            unlink "cpanspec.error";
        }
    }

    {
        my $cmd = "osc addremove";
        debug("CMD $cmd");
        system $cmd and die "Error executig '$cmd': $?";
        if ($args->{ask_commit}) {
            my $answer = prompt("Commit? [Y/n]") || 'Y';
            if ($answer ne 'Y') {
                info("$pkg - no commit");
                return;
            }
        }

        $cmd = "osc ci -mupdate";
        debug("CMD $cmd");
        system $cmd and die "Error executig '$cmd': $?";
    }
    return;
}

sub update_status {
    my ($self, $letter) = @_;
    $self->lockdata;

    my $states = $self->fetch_status($letter);
    my $upstream = $self->from_cpan_file($letter);
    my $obs_info = $self->fetch_obs_info($letter);
    for my $dist (sort keys %$upstream) {
        my $pkg = "perl-$dist";
        my $info = $upstream->{ $dist };
        my $dist_status = $states->{ $dist };
        my $obs_ok = $obs_info->{ $pkg }->{ok} // 0;
        my $obs_tar = $obs_info->{ $pkg }->{archive} || '';

        my ($upstream_version, $upstream_url) = @$info;
        my $upstream_tar = basename $upstream_url;

        my $status = 'new';
        if ($dist_status) {
            $status = $dist_status->[0];

            if ($status =~ m/^error/) {
            }
            elsif (not $obs_tar) {
                $status = 'new';
            }
            elsif ($obs_tar eq $upstream_tar) {
                $status = 'done';
            }
            else {
                $status = 'todo';
            }
        }
        else {
            if (not $obs_tar) {
                $status = 'new';
            }
            elsif ($obs_tar eq $upstream_tar) {
                $status = 'done';
            }
            else {
                $status = 'todo';
            }
        }
        $dist_status = [
            $status, $upstream_version, $upstream_url, $obs_tar, $obs_ok,
        ];

        $states->{ $dist } = $dist_status;

    }
    $self->write_status($letter, $states);

    $self->unlockdata;
}

sub update_status_perl {
    my ($self) = @_;
    $self->lockdata;
    my $apiurl = $self->apiurl;
    my $data = $self->data;

    my $perl_projects = "$data/perl.xml";
    my $cmd = "osc -A $apiurl api /status/project/devel:languages:perl > $perl_projects";
    debug("CMD $cmd");
    system $cmd;
    my $existing = XMLin($perl_projects)->{package};

    my $states = $self->fetch_status_perl();
    my $upstream = {};
    for my $letter ('A' .. 'Z') {
        my $up = $self->from_cpan_file($letter);
        %$upstream = ( %$upstream, %$up );
    }
    for my $dist (sort keys %$upstream) {
        my $pkg = "perl-$dist";
        next unless defined $existing->{ $pkg };
        my $ex = $existing->{ $pkg };
        my $ex_version = $ex->{version};
        my $ex_version_normal = eval { version->parse($ex_version || 0) };
        next unless $ex_version_normal;
        my $info = $upstream->{ $dist };
        my $dist_status = $states->{ $dist };

        my ($upstream_version, $upstream_url) = @$info;
        my $upstream_version_normal = eval {
            version->parse($upstream_version)
        };
        my $upstream_tar = basename $upstream_url;

        my $status = 'new';
        if ($dist_status) {
            $status = $dist_status->[0];
        }

        if ($status =~ m/^error/) {
        }
        elsif (not $ex_version) {
            $status = 'new';
        }
        elsif ($ex_version_normal == $upstream_version_normal) {
            $status = 'done';
        }
        elsif ($ex_version_normal > $upstream_version_normal) {
            $status = 'older';
        }
        else {
            $status = 'todo';
        }

        $dist_status = [
            $status, $upstream_version, $upstream_url, $ex_version_normal,
        ];

        $states->{ $dist } = $dist_status;

    }
    $self->write_status('perl', $states);

    $self->unlockdata;
}

sub lockdata {
    my ($self) = @_;
    my $data = $self->data;
    mkdir $data;
    return 1 if $self->locked;

    my $lockfile = "$data/lockfile";
    my $cmd = "lockfile -1 -r 5 $lockfile";
    system $cmd
        and die "Error using lockfile: $?. Is another process running?";

    $self->locked(1);
}

sub unlockdata {
    my ($self) = @_;
    return 1 unless $self->locked;

    my $data = $self->data;
    my $lockfile = "$data/lockfile";
    unlink $lockfile or die $!;

    $self->locked(0);
}

1;
