package Finance::Bank::CreditMut;
use strict;
use Carp qw(carp croak);
use WWW::Mechanize;
use vars qw($VERSION);

$VERSION = 0.01;

=pod

=head1 NAME

Finance::Bank::CreditMut -  Check your Crédit Mutuel accounts from Perl

=head1 SYNOPSIS

 use Finance::Bank::CreditMut;

 my @accounts = Finance::Bank::CreditMut->check_balance(
    username => "$username",  # Be sure to put the numbers
    password => "$password",  # between quote.
 );

 foreach my $account ( @accounts ){
    local $\ = "\n";
    print "       Name ", $account->name;
    print " Account_no ", $account->account_no;
    print "  Statement\n";

    foreach my $statement ( $account->statements ){
        print $statement->as_string;
    }
 }

=head1 DESCRIPTION

This module provides a rudimentary interface to the CyberMut online
banking system at L<https://www.creditmutuel.fr/>. You will need
either Crypt::SSLeay or IO::Socket::SSL installed for HTTPS support
to work with LWP.

The interface of this module is directly taken from Briac Pilpré's
Finance::Bank::BNPParibas.

=head1 WARNING

This is code for B<online banking>, and that means B<your money>, and
that means B<BE CAREFUL>. You are encouraged, nay, expected, to audit
the source of this module yourself to reassure yourself that I am not
doing anything untoward with your banking data. This software is useful
to me, but is provided under B<NO GUARANTEE>, explicit or implied.

=head1 METHODS

=head2 check_balance( username => $username, password => $password, ua => $ua )

Return a list of account (F::B::CM::Account) objects, one for each of
your bank accounts. You can provide to this method a WWW::Mechanize
object as third argument. If not, a new one will be created.

=cut

sub check_balance {
    my ( $class, %opts ) = @_;
    croak "Must provide a password" unless exists $opts{password};
    croak "Must provide a username" unless exists $opts{username};

    my @accounts;

    $opts{ua} ||= WWW::Mechanize->new(
        agent      => __PACKAGE__ . "/$VERSION ($^O)",
        cookie_jar => {},
    );

    my $self = bless {%opts}, $class;

    my $orig_r;
    my $count = 0;
    {
        $orig_r = $self->{ua}->get("https://www.creditmutuel.fr");
        # loop detected, try again
        ++$count;
        redo unless $orig_r->content || $count > 13;
    }
    croak $orig_r->error_as_HTML if $orig_r->is_error;

    {
        local $^W;  # both fields_are read-only
        my $click_r = $self->{ua}->submit_form(
            form_number => 1,
            fields      => {
                _cm_user => $self->{username},
                _cm_pwd  => $self->{password},
            }
        );
        croak $click_r->error_as_HTML if $click_r->is_error;
    }   
    
    $self->{ua}->follow_link(text_regex => qr/vos\s+comptes/i);

    foreach ( $self->{ua}->links() ) {
        next unless $_->[0] =~ /mouvements\.cgi/;
        $self->{ua}->get('https://www.creditmutuel.fr/banque/' . $_->[0]);
        $self->{ua}->follow_link(text_regex => qw/XP/);

        push @accounts,
          Finance::Bank::CreditMut::Account->new( $_->[1], $self->{ua}->content );
    }
    @accounts;
}

package Finance::Bank::CreditMut::Account;

=pod

=head1 Account methods

=head2 sort_code()

Return the sort code of the account. Currently, it returns an
undefined value.

=head2 name()

Returns the human-readable name of the account.

=head2 account_no()

Return the account number, in the form C<XXXXXXXXX YY>, where X and Y
are numbers.

=head2 balance()

Returns the balance of the account. Currently, it returns an undefined
value.

=head2 statements()

Return a list of Statement object (Finance::Bank::CreditMut::Statement).

=cut

sub new {
    my $class = shift;
    my $name = shift;
    $name =~ /(\d+.\d+)\s+(.*)/ or warn "!!";
    (my $account_no, $name) = ($1, $2);
    $account_no =~ s/\D/ /g; # remove non-breaking space.

    chomp( my @content = split ( /\015\012/, shift ));
    my $header = shift @content;

    my @statements;
    push @statements, Finance::Bank::CreditMut::Statement->new($_) foreach @content;

    bless {
        name       => $name,
        account_no => $account_no,
        sort_code  => undef,
        date       => undef,
        balance    => undef,
        statements => [@statements],
    }, $class;
}

sub sort_code  { undef }
sub name       { $_[0]->{name} }
sub account_no { $_[0]->{account_no} }
sub balance    { $_[0]->{balance} }
sub statements { @{ $_[0]->{statements} } }

package Finance::Bank::CreditMut::Statement;

=pod

=head1 Statement methods

=head2 date()

Returns the date when the statement occured, in DD/MM/YY format.

=head2 description()

Returns a brief description of the statement.

=head2 amount()

Returns the amount of the statement (expressed in Euros or the account's
currency).

=head2 as_string($separator)

Returns a tab-delimited representation of the statement. By default, it
uses a tabulation to separate the fields, but the user can provide its
own separator.

=cut

sub new {
    my $class     = shift;
    my $statement = shift;

    my @entry = split ( /;/, $statement );

    $entry[0] =~ s/\d\d(\d\d)$/$1/;
    $entry[1] = $entry[2] unless $entry[1] ne '';
    $entry[1] =~ s/,/./;
    $entry[1] =~ tr/'//d;
    $entry[1] += 0; # turn into a number

    bless [ @entry[ 0,3,1 ] ], $class;
}

sub date        { $_[0]->[0] }
sub description { $_[0]->[1] }
sub amount      { $_[0]->[2] }

sub as_string { join ( $_[1] || "\t", @{ $_[0] } ) }

1;

__END__

=head1 COPYRIGHT

Copyright 2002-2003, Cédric Bouvier. All Rights Reserved. This module can
be redistributed under the same terms as Perl itself.

=head1 AUTHOR

Cédric Bouvier <cbouvi@free.fr>

Thanks to Simon Cozens for releasing Finance::Bank::LloydsTSB and to Briac Pilpré for Finance::Bank::BNPParibas.

=head1 SEE ALSO

Finance::Bank::BNPParibas, WWW::Mechanize

=cut

