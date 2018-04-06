package LibreCat::Model::Publication;

use Catmandu::Sane;
use LibreCat;
use LibreCat::App::Catalogue::Controller::File     ();
use LibreCat::App::Catalogue::Controller::Material ();
use Catmandu::Fix::add_citation;
use Moo;
use namespace::clean;

with 'LibreCat::Model';

sub BUILD {
    my ($self) = @_;
    $self->append_before_add(
        [

            # TODO this is very dirty and executes even if validation fails
            file             => '_store_file',
            related_material => '_store_related_material',

            # TODO move to config
            citation => Catmandu::Fix::add_citation->new,
        ]
    );
}

sub delete {
    my ($self, $id, %opts) = @_;

    my $rec = $self->get($id) || return;

    if ($rec->{oai_deleted} || $rec->{status} eq 'public') {
        $rec->{oai_deleted} = 1;
        $rec->{locked}      = 1;
    }

    $rec->{date_deleted} = LibreCat->timestamp;
    $rec->{status}       = 'deleted';

    # TODO can't call add because date_deleted & co aren't whitelisted
    $self->store($rec, %opts);
    $self->index($rec, %opts);

    $id;
}

sub _store_file {
    my ($self, $rec) = @_;
    LibreCat::App::Catalogue::Controller::File::handle_file($rec);
    $rec;
}

sub _store_related_material {
    my ($self, $rec) = @_;
    if ($rec->{related_material}) {
        LibreCat::App::Catalogue::Controller::Material::update_related_material(
            $rec);
    }
    $rec;
}

1;
