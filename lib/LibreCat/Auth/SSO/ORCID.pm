package LibreCat::Auth::SSO::ORCID;

use Catmandu::Sane;
use Catmandu::Util qw(:check :is);
use WWW::ORCID;
use Moo;
use Plack::Request;
use Plack::Session;
use LibreCat::Auth::SSO::Util qw(uri_for);
use URI;
use JSON;
use namespace::clean;

with 'LibreCat::Auth::SSO';

has sandbox => (is => 'ro', required => 0);
has debug   => (is => 'ro', required => 0);
has client_id =>
    (is => 'ro', isa => sub {check_string($_[0]);}, required => 1);
has client_secret =>
    (is => 'ro', isa => sub {check_string($_[0]);}, required => 1);
has _orcid_client =>
    (is => 'ro', lazy => 1, builder => '_build_orcid_client');
has _json => (is => 'ro', lazy => 1, default => sub {JSON->new()->utf8(1);});

sub _build_orcid_client {
    my $self = $_[0];
    WWW::ORCID::API->new(sandbox => $self->sandbox, debug => $self->debug);
}

sub to_app {
    my $self = $_[0];

    sub {

        my $env = $_[0];

        my $request = Plack::Request->new($env);
        my $session = Plack::Session->new($env);
        my $params  = $request->query_parameters();

        my $auth_sso = $self->get_auth_sso($session);

        #already got here before
        if (is_hash_ref($auth_sso)) {

            return [302, [Location => $self->authorization_url], []];

        }

        my $callback = $params->get('_callback');

        #callback phase
        if (is_string($callback)) {

            my $error             = $params->get('error');
            my $error_description = $params->get('error_description');

            if (is_string($error)) {

                return [
                    500, ["Content-Type" => "text/html"],
                    [$error_description]
                ];

            }
            my $res = $self->_orcid_client->new_access_token(
                $self->client_id, $self->client_secret,
                grant_type => 'authorization_code',
                code       => $params->get('code')
            );

            my $doc = $self->_json()->encode($res);

            $self->set_auth_sso($session,
                {type => "ORCID", response => $doc});

            return [302, [Location => $self->authorization_url], []];
        }

        #request phase
        else {

            my $redirect_uri = URI->new(uri_for($env, $request->script_name));
            $redirect_uri->query_form({_callback => "true"});

            my $auth_url
                = URI->new($self->_orcid_client->sandbox
                ? 'http://sandbox.orcid.org/oauth/authorize'
                : 'http://orcid.org/oauth/authorize');
            $auth_url->query_form(
                {
                    show_login    => 'true',
                    client_id     => $self->client_id,
                    scope         => '/orcid-profile/read-limited',
                    response_type => 'code',
                    redirect_uri  => $redirect_uri,
                }
            );

            [302, [Location => $auth_url->as_string()], []];

        }
    };
}

1;

=pod

=head1 NAME

LibreCat::Auth::SSO::ORCID - implementation of LibreCat::Auth::SSO for ORCID

=head1 SYNOPSIS

    #in your app.psgi

    builder {


        #Register THIS URI in ORCID as a new redirect_uri

        mount '/auth/orcid' => LibreCat::Auth::SSO::ORCID->new(
            client_id => "APP-1",
            client_secret => "mypassword",
            debug => 1,
            sandbox => 1,
            authorization_url => "${base_url}/auth/orcid/callback"
        )->to_app;

        #DO NOT register this uri as new redirect_uri in ORCID

        mount "/auth/orcid/callback" => sub {

            my $env = shift;
            my $session = Plack::Session->new($env);
            my $auth_sso = $session->get('auth_sso');

            #not authenticated yet
            unless($auth_sso){

                return [403,["Content-Type" => "text/html"],["forbidden"]];

            }

            #process auth_sso (white list, roles ..)

            #auth_sso is a hash reference:
            #{ type => "ORCID", response => "<response-from-orcid>" }
            #the response from orcid is in this case a json string containing the following data:
            #
            #{
            #    'orcid' => '<orcid>',
            #    'access_token' => '<access_token>',
            #    'refresh_token' => '<refresh-token>',
            #    'name' => '<name>',
            #    'scope' => '/orcid-profile/read-limited',
            #    'token_type' => 'bearer',
            #    'expires_in' => '<expiration-date>'
            #}

            #you can reuse the 'orcid' and 'access_token' to get the user profile

            [200,["Content-Type" => "text/html"],["logged in!"]];

        };

    };


=head1 DESCRIPTION

This is an implementation of L<LibreCat::Auth::SSO> to authenticate against a ORCID (OAuth) server.

It inherits all configuration options from its parent.

=head1 CONFIG

Register the uri of this application in ORCID as a new redirect_uri.

DO NOT register the authorization_url in ORCID as the redirect_uri!

=over 4

=item client_id

client_id for your application (see developer credentials from ORCID)

=item client_secret

client_secret for your application (see developer credentials from ORCID)

=item sandbox

0|1. Defaults to '0'. When set to '1', this api makes use of http://sandbox.orcid.org instead of http://orcid.org.

=item debug

0|1. Defaults to '0'. Prints debug messages to STDERR.

=back

=head1 SEE ALSO

L<LibreCat::Auth::SSO>

=cut
