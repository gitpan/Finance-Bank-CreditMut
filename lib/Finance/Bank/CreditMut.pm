package Finance::Bank::CreditMut;
use strict;
use Carp qw(carp croak);
use WWW::Mechanize;
use HTML::TableExtract;
use vars qw($VERSION);

$VERSION = 0.05;

# $Id: CreditMut.pm,v 1.7 2003/12/09 08:38:40 cbouvi Exp $
# $Log: CreditMut.pm,v $
# Revision 1.7  2003/12/09 08:38:40  cbouvi
# Changed $VERSION
#
# Revision 1.6  2003/12/09 08:37:58  cbouvi
# CMut once again changed the wording on their site
#
# Revision 1.5  2003/10/14 21:34:24  cbouvi
# Hit directly the /comptes/ page, instead of following a link there from the home page. The accounts appear immediately
# instead of being one click away.
#
# Revision 1.4  2003/08/30 21:08:04  cbouvi
# Changed $VERSION
#
# Revision 1.3  2003/08/30 21:07:10  cbouvi
# Changed the parsing of CSV data to accomodate the new Value Date column
#
# Revision 1.2  2003/06/13 10:13:59  cbouvi
# Added retrieval of account balances.
# Retrieval of account statements is now post-poned to the actual call to
# method statements()
# Added method currency() for accounts.
# Added comments
#

=pod

=head1 NAME

Finance::Bank::CreditMut -  Check your Cr�dit Mutuel accounts from Perl

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

This module provides a rudimentary interface to the CyberMut online banking
system at L<https://www.creditmutuel.fr/>. You will need either
Crypt::SSLeay or IO::Socket::SSL installed for HTTPS support to work with
LWP.

The interface of this module is directly taken from Briac Pilpr�'s
Finance::Bank::BNPParibas.

=head1 WARNING

This is code for B<online banking>, and that means B<your money>, and that
means B<BE CAREFUL>. You are encouraged, nay, expected, to audit the source
of this module yourself to reassure yourself that I am not doing anything
untoward with your banking data. This software is useful to me, but is
provided under B<NO GUARANTEE>, explicit or implied.

=head1 METHODS

=head2 check_balance( username => $username, password => $password, ua => $ua )

Return a list of account (F::B::CM::Account) objects, one for each of your
bank accounts. You can provide to this method a WWW::Mechanize object as
third argument. If not, a new one will be created.

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
        $orig_r = $self->{ua}->get("https://www.creditmutuel.fr/comptes/");
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
    
    # The current page contains a table displaying the accounts and their
    # balances. 

    my $te = new HTML::TableExtract(headers => [
        q{Pour consulter un relev� d'op�rations, cliquez sur un compte},
        q{D�bit},
        q{Cr�dit},
    ]);
    $te->parse($self->{ua}->content());
    for my $ts ( $te->table_states() ) {
        foreach ( $ts->rows() ) {
            # The name actually also contains the account number.
            # Finance::Bank::CreditMutuel::Account::new will take care of
            # splitting.
            my ($name, $dept, $asset) = @$_;
            for ($name, $dept, $asset) {
                s/^\s+|\s+$//g; # remove leading and trailing whitespace
                s/\s+/ /g; # collapse all whitespace to one single blank
            }
            my $link = $self->{ua}->find_link(text_regex => qr/$name/);

            # we only care about accounts that are displayed with
            # 'mouvements.cgi' (mortgages use another page that does not
            # provide CSV downloads. Maybe a future version will handle
            # this)
            next unless $link && $link->[0] =~ /mouvements\.cgi/;
            for ($dept, $asset) {
                tr/,/./;
                tr/-+.A-Z0-9//cd;
            }
            # Negative and positive balances are displayed in different
            # columns: take either one and split the currency code at the
            # same time.
            my ($balance,$currency) = $dept || $asset =~ /(.*?)([A-Z]+)$/;
            $balance += 0; # turn string into a number
            push @accounts, Finance::Bank::CreditMut::Account->new(
                $name,
                $currency,
                $balance,
                $self->{ua},
                "https://www.creditmutuel.fr/banque/$$link[0]",
            );
        }
    }
    @accounts;
}

package Finance::Bank::CreditMut::Account;

=pod

=head1 Account methods

=head2 sort_code()

Return the sort code of the account. Currently, it returns an undefined
value.

=head2 name()

Returns the human-readable name of the account.

=head2 account_no()

Return the account number, in the form C<XXXXXXXXX YY>, where X and Y are
numbers.

=head2 balance()

Returns the balance of the account.

=head2 statements()

Return a list of Statement object (Finance::Bank::CreditMut::Statement).

=head2 currency()

Returns the currency of the account as a three letter ISO code (EUR, CHF,
etc.)

=cut

sub new {
    my $class = shift;
    my ($name, $currency, $balance, $ua, $url) = @_;
    $name =~ /(\d+.\d+)\s+(.*)/ or warn "!!";
    (my $account_no, $name) = ($1, $2);
    $account_no =~ s/\D/ /g; # remove non-breaking space.

    bless {
        name       => $name,
        account_no => $account_no,
        sort_code  => undef,
        date       => undef,
        balance    => $balance,
        currency   => $currency,
        ua         => $ua,
        url        => $url,
    }, $class;
}

sub sort_code  { undef }
sub name       { $_[0]->{name} }
sub account_no { $_[0]->{account_no} }
sub balance    { $_[0]->{balance} }
sub currency    { $_[0]->{currency} }
sub statements { 

    my $self = shift;

    @{
        $self->{statements} ||= do {
            $self->{ua}->get($self->{url});
            $self->{ua}->follow_link(text_regex => qr/XP/);
            chomp(my @content = split /\015\012/, $self->{ua}->content());
            shift @content;
            [map Finance::Bank::CreditMut::Statement->new($_), @content];
        };
    };
}

package Finance::Bank::CreditMut::Statement;

=pod

=head1 Statement methods

=head2 date()

Returns the date when the statement occured, in DD/MM/YY format.

=head2 description()

Returns a brief description of the statement.

=head2 amount()

Returns the amount of the statement (expressed in Euros or the account's
currency). Although the Cr�dit Mutuel website displays number in continental
format (i.e. with a coma as decimal separator), amount() returns a real
number.

=head2 as_string($separator)

Returns a tab-delimited representation of the statement. By default, it uses
a tabulation to separate the fields, but the user can provide its own
separator.

=cut

sub new {
    my $class     = shift;
    my $statement = shift;

    my @entry = split ( /;/, $statement );

    $entry[0] =~ s/\d\d(\d\d)$/$1/; # year on 2 digits only
    # negative number are displayed in a separate column. Move them to the same
    # one as positive numbers.
    $entry[2] = $entry[3] unless $entry[2] ne '';
    $entry[2] =~ s/,/./;
    $entry[2] =~ tr/'//d; # remove thousand separators
    $entry[2] += 0; # turn into a number

    bless [ @entry[ 0,4,2 ] ], $class;
}

sub date        { $_[0]->[0] }
sub description { $_[0]->[1] }
sub amount      { $_[0]->[2] }

sub as_string { join ( $_[1] || "\t", @{ $_[0] } ) }

1;

__END__

=head1 COPYRIGHT

Copyright 2002-2003, C�dric Bouvier. All Rights Reserved. This module can be
redistributed under the same terms as Perl itself.

=head1 AUTHOR

C�dric Bouvier <cbouvi@cpan.org>

Thanks to Simon Cozens for releasing Finance::Bank::LloydsTSB and to Briac
Pilpr� for Finance::Bank::BNPParibas.

=head1 SEE ALSO

Finance::Bank::BNPParibas, WWW::Mechanize

=cut

