# ------------------------------ MNI Header ----------------------------------
#@NAME       : NeuroDB::Mail
#@DESCRIPTION: Perform common tasks relating to sending emails
#@EXPORT     : 
#@EXPORT_OK  : mail
#@EXPORT_TAGS: 
#@USES       : Exporter
#@REQUIRES   : 
#@VERSION    : $Id: Mail.pm,v 3.0 2004/03/25 20:32:15 jharlap Exp $
#@CREATED    : 2003/04/11, Jonathan Harlap
#@MODIFIED   : 
#@COPYRIGHT  : Copyright (c) 2003 by Jonathan Harlap, McConnell Brain Imaging
#              Centre, Montreal Neurological Institute, McGill University.
#-----------------------------------------------------------------------------

package NeuroDB::Mail;

use Exporter ();

$VERSION = 0.1;
@ISA = qw(Exporter);

@EXPORT = qw();

@EXPORT_OK = qw(mail);

# ------------------------------ MNI Header ----------------------------------
#@NAME       : mail
#@INPUT      : $to        => mungeable list of addresses (either a comma seperated list or an arrayref)
#              $subject   => subject of message
#              $body      => body of message
#              $cc        => ref to array of addresses         (opt)
#              $bcc       => ref to array of addresses         (opt)
#              $addlhdr   => hashref of additional headers     (opt)
#@OUTPUT     : none to STDOUT/STDERR
#@RETURNS    : 1 if success, 0 if failure
#@DESCRIPTION: sends a message via email (using sendmail -t)
#@METHOD     : 
#@GLOBALS    : 
#@CALLS      : 
#@CREATED    : 2003/04/10, Jonathan Harlap
#@MODIFIED   : 
#-----------------------------------------------------------------------------
sub mail {
    my ($to, $subject, $body, $cc, $bcc, $addlhdr) = @_;

    # fail immediately if we don't have a defined to, subj, and body.
    return 0 
        unless defined $to && $to ne '' 
        && defined $subject && $subject ne '' 
        && defined $body && $body ne '';

    # start building the message header
    my @headers = ();

    # add the To
    push @headers, "To: "._munge_headers($to);

    # add the subject
    push @headers, "Subject: $subject";

    # add Cc, if appropriate
    push @headers, "Cc: "._munge_headers($cc) if defined $cc;

    # add Bcc, if appropriate
    push @headers, "Bcc: "._munge_headers($bcc) if defined $bcc;

    # add the date
#    my $date = `date -R`;
#    chomp($date);
#    push @headers, "Date: $date";

    # add any additional headers
    push @headers, _munge_headers($addlhdr) if defined $addlhdr && ref($addlhdr) eq 'HASH';

    # the first whitespace line
    push @headers, "";

    # open the pipe to sendmail
    open MAIL, "| /usr/lib/sendmail -t -i" or return 0;
    #open MAIL, "> test.msg";

    # send the headers
    print MAIL join("\n", @headers);

    # send the body
    print MAIL $body;

    # send the mail!
    close MAIL;

    return 1;
}

# ------------------------------ MNI Header ----------------------------------
#@NAME       : _munge_headers
#@INPUT      : $input     => a scalar or reference of some kind
#@OUTPUT     : none
#@RETURNS    : a string consisting of probabilistically valid headers
#@DESCRIPTION: munges scalars, scalarrefs, arrayrefs, and hashrefs
#              a word of warnings: it runs recursively on hashrefs
#              and does no error checking!
#@METHOD     : 
#@GLOBALS    : 
#@CALLS      : 
#@CREATED    : 2003/04/10, Jonathan Harlap
#@MODIFIED   : 
#-----------------------------------------------------------------------------
sub _munge_headers {
    my ($input) = @_;
    
    # just return it if it's not a reference
    return $input unless ref $input;

    # if it's a scalar ref, return the scalar
    if(ref($input) eq 'SCALAR') {
        return $$input;
    }

    # join on a comma if it's an arrayref
    if(ref($input) eq 'ARRAY') {
        return join(',', @$input);
    }

    # munge hashrefs
    if(ref($input) eq 'HASH') {
        my $hdr = '';
        # for each key
        foreach my $key (keys %$input) {
            # add a new line to the header, consisting of the munge
            $hdr .= "$key: "._munge_headers($$input{$key})."\n";
        }
        return $hdr;
    }
}
