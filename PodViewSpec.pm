package PodViewSpec;
use base "Pod::POM::View::Text";

# overwrite the link default - we don't want
# to reference to "the manpage"
sub view_seq_link {
    my ($self, $link) = @_;
    return $link;
}


1;
