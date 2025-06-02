FROM opensuse/leap:15.2

RUN zypper refresh \
    && zypper install -y \
        osc \
        perl \
        perl-YAML-LibYAML \
        perl-XML-Simple \
        perl-Parse-CPAN-Packages \
        procmail \
        wget \
        vim \
        git \
        perl-Text-Autoformat \
        perl-YAML \
        perl-Pod-POM \
        perl-libwww-perl \
        perl-Class-Accessor-Chained \
        perl-Algorithm-Diff \
        perl-Module-Build-Tiny \
        perl-ExtUtils-Depends \
        perl-ExtUtils-PkgConfig \
        obs-service-format_spec_file \
    && true


RUN cd /tmp && wget http://www.cpan.org/modules/02packages.details.txt.gz

ENV LANG=en_US.UTF-8 \
    LC_CTYPE="en_US.UTF-8" \
    LC_NUMERIC="en_US.UTF-8" \
    LC_TIME="en_US.UTF-8" \
    LC_COLLATE="en_US.UTF-8"


# perl /cpanspec/cpanspec -v -f --skip-changes --pkgdetails /tmp/02packages.details.txt.gz tarball

