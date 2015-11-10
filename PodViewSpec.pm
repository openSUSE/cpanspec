package PodViewSpec;
use parent qw( Pod::POM::View::Text );
use Pod::POM::View;
use Text::Wrap;

# overwrite the link default - we don't want
# to reference to "the manpage"
sub view_seq_link {
    my ($self, $link) = @_;
    return $link;
}

sub view_item {
    my ($self, $item) = @_;
    my $indent = ref $self ? \$self->{ INDENT } : \$INDENT;
    my $pad = ' ' x $$indent;
    local $Text::Wrap::unexpand = 0;
    my $title = $item->title->present($self);
    if ($title !~ m/^\s*$/ && $title ne '*') {
	$title = wrap($pad . '* ', $pad . '  ', $title);

	$$indent += 2;
	my $content = $item->content->present($self);
	$$indent -= 2;

	return "$title\n\n$content";
    } else {
	my $content = $item->content->present($self);
	chomp $content;
	return "  * $content\n";
    }
}

1;
