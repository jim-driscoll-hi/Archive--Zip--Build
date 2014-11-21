package Archive::Zip::Build;
use strict;
use warnings;
our $DEBUG = 0;

use version; our $VERSION = version->declare("v0.1.0");

# Copyright (c) 2012, Heart Internet Ltd
# All rights reserved.
# 
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#     * Redistributions of source code must retain the above copyright
#       notice, this list of conditions and the following disclaimer.
#     * Redistributions in binary form must reproduce the above copyright
#       notice, this list of conditions and the following disclaimer in the
#       documentation and/or other materials provided with the distribution.
#     * Neither the name of the <organization> nor the
#       names of its contributors may be used to endorse or promote products
#       derived from this software without specific prior written permission.
# 
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL <COPYRIGHT HOLDER> BE LIABLE FOR ANY
# DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
# (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
# LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
# ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
# SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

use Compress::Zlib;
use Carp;

=head1 NAME

Archive::Zip::Build

=head1 DESCRIPTION

An implementation of zip support, designed to be akin to IO::Compress::Zlib

=head1 SYNOPSIS

  use Archive::Zip::Build;
  my $mz = new Archive::Zip::Build(\*STDOUT);
  $mz->print_item(
    Name=>$filename."/",
    Time=>$mtime,
    ExtAttr=>$full_mode<<16,
    exTime => [$atime, $mtime, $ctime],
    Method => "store",
    ExtraFieldLocal=>\@extra_fields_local,
  );
  $mz->print_item(
    Name=>$filename,
    Time=>$mtime,
    ExtAttr=>$full_mode<<16,
    exTime => [$atime, $mtime, $ctime],
    Method => "deflate,
    ExtraFieldLocal=>\@extra_fields_local,
    content => $content,
  );
  $mz->close;

=head1 FORMAT OVERVIEW

At a very coarse level, zip data is like a multipart/mixed "body" with a
TOC tagged on to the end: You get header+body, header+body... TOC. The
individual chunks are almost a zip file in themselves, except that the
TOC is mandatory; in theory, compressing in the individual data chunks
means that you can seek freely in the zip file, ie. it takes the same
amount of time to extract any given archive member regardless of where
it is in the archive. Also, by having a TOC at the end, you can inspect
the archive without reading the whole thing - although this only works
when you can do random seeks (ie, on an actual file).

Strictly speaking, as described below, building a zip file from a stream
means that the header cannot contain the compressed size, which destroys
any ability to seek forwards over compressed data.

=head1 FORMAT DETAIL

The basic format of a zip file is:

=over

=item header 1 (possibly partial)

This is information about the file or directory, including the filename and
permissions. UNIX-style relative non-parent filenames only, and if you want to
say it's a directory, there needs to be a trailling /.

For files which are to be compressed, some of the data (CRC and compressed size)
will generally not be known at this stage.

=over

=item extra header 1-1

A custom header (signature(2), length(2), data). Common signatures you'd see are
UT (better timestamps) and ux (unix attributes).

=item extra header 1-2

=item ...

=back

=item data 1 (possibly empty)

For directories, or empty files, this is skipped. For some files, this will be
the literal file data (pkzip usually compresses virtually everything, but it is
strictly optional, and counterproductive for small files and some already-
compressed files).

NOTE: this means that very small files are likely to be verbatim in the zip
file, and high-entropy files (like JPEGs) might also, allowing you to at least
search for their magic sequence.

=item data descriptor 1 (possibly non-existent)

If the CRC/size/compressed size weren't known in header 1, they can be included
here, IF the data in "data 1" has its own end-of-stream marker - if it doesn't,
the zip implementation would never know where the data ends, and would have to
presume just before the start of header 2. This CAN have a leading signature,
which is probably present to ease debugging.

Basically this is just an extension of header 1 for when data has been
compressed.

=item header 2

=item data 2

=item ...

=item central directory

This is where zip implementations will go looking for the file list. It means
that you can tell a lot without having to scan the whole file.

=over

=item central directory header 1

Almost exactly as header 1, the main difference being that CRC and compressed
size are guaranteed to be known by this point. There are subtle differences,
though, particularly in the extra headers. In principle, this provides enough
information to list a file, but not enough to extract it - eg, it might exclude
resource forks, access times, post-processing filters, things like that.

Critically, this tells you where to find the corresponding original header.

=item central directory header 2

=item ...

=item zip64 end of central directory (optional)

This is the 64-bit counterpart of the end-of-central-directory record below.
Length is variable.

=item zip64 end of central directory locator (required with the above)

This just points to the start of the zip64 EOCD.

=item end of central directory

There's some data about the zip file as a whole at this stage, including its
size and how far back the central directory starts. This block is NEARLY fixed
in size, the variable part being the rarely-used zip file comment, so you can
pretty much seek to end minus 22 bytes, read a chunk, seek backwards some more,
read a chunk, and then seek backwards to your target file. Obviously this isn't
a stream-readable pattern, but if (because the world has ended) you somehow end
up with a .zip.gz file or something, you can get through by continuously
reading forwards until you hit the data you need.

The most trivial zip file contains ONLY an end-of-central-directory block.

=back

=back

=head1 DEBUGGING

  od -c -t x1

All the interesting blocks start with P K (single-digit number) (single-digit
number). They are all specified somewhere - search for "appnote.txt" or
"appnote.iz" to see what does what, but you should be able to work it out from
the above. Extra headers tend to start with two letters which are somewhat
mnemonic for their purpose.

When reading the spec (and even the code here), bear in mind that little-endian
architecture is assumed, even for cases where the value to be inserted is not
in fact a number (example: 0x06054b50 maps to PK\05\06 not \06\05KP) so you will
have to byte-reverse the source values to get the file value, and vice versa.
In particular, you should note that <<8 (shift left 8 bits) does NOT put a
value a byte to the left of its normal location: rather it multiplies by 2^8,
meaning that the value is in practice shifted RIGHT by one byte.

=head1 METHODS

=head2 new($fh, \%options)

Creates an object tied to a filehandle.

Please note that you don't need to explicitly ask for zip64 support,
you will be given it as standard.

Options are:

=over

=item no_zip64

Disable zip64 support. This will result in a confess() if zip64 is needed,
so please only set this for contexts where you know the result will be
well under 2GB (eg. < 100MB) and you need the compatibility.

=back

=cut

sub new {
  my ($class, $fh, $options) = @_;
  $options||={};
  
  my $block_size = 1048576;
  my $self = {
    zip64 => $options->{no_zip64} ? 0 : 1,
    block_size => $block_size,
    central_headers=>[],
    fh=>$fh,
    written=>0,
  };

  # This SHOULD be 63, but it seems to be 20 everywhere.
  $self->{spec_version} = $self->{zip64} ?
    45 : # appnote v4.5 = zip64 support
    20 ; # appnote v2.0 = common (old) version

  return bless($self, $class);
}

=head2 print_item(%options)

Writes out a zip local header (and remembers it), and the content.

Options are:

=over

=item Name (required)

The filename, unix-style. Directories must end with /, and anything starting
with "../" or "./" or "/" will be rejected.

=item Time (required)

The zip-internal modification time. Provide a UNIX timestamp and the correct
format will be worked out.

=item ExtAttr

The extended-attribute value - a 32-bit number. On UNIX, the high 16 bits should
be the mode.

=item exTime

The atime, mtime, and ctime, in that order. You can leave any of them as undef.

=item Method

"deflate" for normal compression or "store" for storing verbatim. Pre-compressed
files may be better stored, as would very short files and directories.

=item content

For the "store" method, the header will be sent late as a CRC is calculated for the data.

Under all circumstances this will be sent (possibly compressed) after the header.

You may provide a filehandle instead of a string, but if you do so then you
MUST provide a size. If you asked for the method "store" then the data will
have to be sucked up to make the CRC, so there's not much point in that case.

If this is undef, it will be treated as empty.

=item ExtraFieldLocal

Miscellaneous extra fields, provided as an array of (packed 16-bit number,
packed data) pairs. Eg.

  [pack("S", 0x7875)=>pack("CCNCN", 1, 4, $uid, 4, $gid)]

=item ExtraField

Basically as ExtraFieldLocal above, but appears elsewhere in the directory.

=item file_comment

A comment for this file; no semantics. This has a length expressed in 16
bits, so it's recommended that you keep the size < 32KB and you must keep
the size < 64KB. If the comment is too long, the result will be nonsense.

It's recommended that you do not provide a comment at all.

=item internal_file_attributes

A hash(ref) of codes to true values indicating some metadata about the
file. Supported options are:

=over

=item ascii

The file is an (ASCII) text file. Essentially this has the same meaning
as FTP ASCII transfer mode, ie. it indicates that the file will still make
sense if you convert the line endings to whatever your system prefers.

=back

=item os_version

The base OS of the system which the file came from. This may affect
parsing of attributes and is expected to affect how line endings are
parsed.

The only known-working value is 3 (UNIX) but you might want to try 0
(DOS, Windows) on appropriate systems.

This MAY be taken as an indication of the OS of the system which actually
created the zip file, so you almost certainly want to set a consistent
value.

=item Size

Completely optional. Use this to save having to know the actual size of
the data. If you're extremely crazy you can use this to ask for a subset
of a file. It's recommended that you determine the size by stat()ing
the filehandle after you open it (if possible).

=back

Please note that large files (2GB+) which are to be stored will still
have to be entirely read before the header can be sent, meaning a wait
of perhaps some minutes. In that situation you might want to use deflate
instead.

=cut

sub _crc32 {
  my ($buffer, $crc) = @_;
  return Compress::Zlib::crc32($buffer, $crc);
}

my $SIZE_IN_DATA_DESCRIPTOR = 0b00000000_00001000;

sub _ts_to_dos_d_t {
  my ($ts) = @_;
  my ($s, $min, $h, $d, $mon, $y)=localtime($ts);
  my $dos_time = ($h << 11) | ($min << 5) | (int($s/2) << 0);
  my $dos_date = (($y + 1900 - 1980) << 9) | (($mon+1) << 5) | ($d << 0);
  return ($dos_date, $dos_time);
}

sub _print {
  my ($self, $content) = @_;
  my $fh = $self->{fh};
  print $fh $content;
  $self->{written}+=length($content); 
}

sub _pack_fake {
  my ($format, @args) = @_;
  my ($nf, @nargs);
  while($format=~s/^([a-z]\d*)//i) {
    my $type = $1;
    my $v = shift(@args);
    if($type eq "Q") {
      # Emulate.
      $nf.="VV";
      push(@nargs, $v & 0xff_ff_ff_ff );
      push(@nargs, $v / (2**32) );
    } else {
      $nf.=$type;
      push(@nargs, $v);
    }
  }
  pack($nf, @nargs);
}

my $g_has_io_scalar; # Used below.

sub print_item {
  my ($self, %options) = @_;
  if(exists $options{Name}) {
    if($options{Name}=~m#^\.{0,2}/# or $options{Name}=~m#/\.\./#) {
      confess "File name '$options{Name}' must be relative and fully contained to be valid in a zip file";
    }
  }
  $options{content} = "" unless defined $options{content};

  warn "Requested size is $options{Size}" if $DEBUG;
  my $computed_size = defined($options{Size}) ?
    $options{Size} :
    length($options{content});

  warn "Size seems to be $computed_size" if $DEBUG;

  my $bit_flag = 0b0000_0000_0000_0000;
  my ($crc32, $compressed_size);
  my $uncompressed_size = $computed_size;

  my $initial_offset = $self->{written};
  my $zip64_needed =
    ($uncompressed_size > 0xef_ff_ff_ff or $initial_offset > 0xef_ff_ff_ff);

  if($zip64_needed and not $self->{zip64}) {
    confess "Zip64 support is needed to do this";
  }

  my $compression_method_n;

  if($options{Method} eq "store") {
    if(ref $options{content}) {
      # Suck it up.
      local $/=undef;
      warn "Reading $computed_size" if $DEBUG;

      if($computed_size < 2**31) {
        my $new_content;
        $options{content}->read($new_content, $computed_size);
        $crc32 = _crc32($new_content);
        $options{content} = $new_content;
      } else {
        ## NOTE: IO::Handle->read maps to perl read, which maps to system
        ## read...  which means you end up with a 32-bit size limit. So
        ## do it in blocks instead.
        require File::Temp;
        my ($fh, $filename) = File::Temp::tempfile("zip-store-XXXXXXXXXX", DIR=>"/tmp");
        my $c;
        my $block_size = $self->{block_size};
        $crc32 = 0;
        for(my $i=0; $i<$computed_size; $i+=$block_size) {
          my $s = ($i+$block_size > $computed_size) ?
            ($computed_size - $i) :
            ($block_size);
          warn "Reading $s" if $DEBUG;
          $options{content}->read($c, $s);
          $crc32 = _crc32($c, $crc32);
          print $fh $c;
        }
        open($options{content}, "<", $filename);
        unlink($filename);
      }
    } else {
      $crc32 = _crc32($options{content});
    }
    $compressed_size = $uncompressed_size;
    $compression_method_n = 0;
  } elsif($options{Method} eq "deflate") {
    $uncompressed_size = 0;
    $crc32 = 0;
    $compressed_size = 0;
    $bit_flag|=$SIZE_IN_DATA_DESCRIPTOR;
    $compression_method_n = 8;
  } else {
    # Anything here MIGHT need to pre-calculate its value to set crc32, etc.
    confess "Unknown method: '$options{method}'";
  }
  my ($dos_date, $dos_time) = _ts_to_dos_d_t($options{Time});

  my $extra_fields_packed = "";
  if($options{exTime}) {
    my @times = @{ $options{exTime} };
    my $time_map_n;
    my @ttu;
    for(0..$#times) {
      if(defined $times[$_]) {
        push @ttu, $times[$_];
        $time_map_n|=1 << (7-$_);
      }
    }
    $options{ExtraFieldLocal}||=[];
    unshift(@{ $options{ExtraFieldLocal} },
      pack("S", 0x5455) => pack("C".("V" x @ttu), $time_map_n, @ttu)
    );
    unshift(@{ $options{ExtraField} },
      pack("S", 0x5455) => pack("C".("V" x @ttu), $time_map_n, defined($times[0]) ? $times[0] : ())
    );
  }

  if($zip64_needed) {
    # 0001 is the signature for zip64
  
    # For some reason, we must show compressed AND uncompressed sizes regardless
    # of whether both are needed as such.

    my $zip64_ei_body = "";
    foreach($uncompressed_size, $compressed_size) {
      $zip64_ei_body.=_pack_fake("Q", $_);
    }
    # I'm ignoring the disk start number completely.
    unshift(@{ $options{ExtraFieldLocal} },
      pack("S", 0x0001) => $zip64_ei_body,
    );
    # It's also added to the non-local headers below.
  }

  if($options{ExtraFieldLocal}) {
    my @efl = @{$options{ExtraFieldLocal}};
    for(my $i=0; $i<scalar(@efl); $i+=2) {
      $extra_fields_packed.=
        $efl[$i+0].
        pack("S", length($efl[$i+1])).
        $efl[$i+1];
    }
  }

  $self->_print(pack("VSSSSSVVVSS",
    0x04034b50, # local file header signature
    $self->{spec_version}, # version needed to extract
    $bit_flag, # general purpose bit flag
    $compression_method_n, # compression method
    $dos_time, # last mod file time
    $dos_date, # last mod file date
    $crc32, # crc-32
    ($zip64_needed ? 0xff_ff_ff_ff : $compressed_size), # compressed size - ffffffff means result will be in zip64 EI
    ($zip64_needed ? 0xff_ff_ff_ff : $uncompressed_size), # uncompressed size - as above.
    length($options{Name}), # file name length
    length($extra_fields_packed), # extra field length
  ));
  $self->_print($options{Name});
  $self->_print($extra_fields_packed);
  if($options{Method} eq "deflate") {
    my $out;
    my $block_size = $self->{block_size};
    my ($d, $status) = Compress::Zlib::deflateInit(
      -Level=>Compress::Zlib::Z_DEFAULT_COMPRESSION,
      -WindowBits => -Compress::Zlib::MAX_WBITS(),
      -Bufsize => $block_size,
    );
    if($status) {
      confess "Deflate error: $status";
    }
    my $c;
    my $read_fh;
    if(ref $options{content}) {
      $read_fh = $options{content};
    } else {
      unless(defined $g_has_io_scalar) {
        $g_has_io_scalar = eval {require IO::Scalar;1};
      }
      
      if($g_has_io_scalar) {
        require IO::Scalar;
        $read_fh = new IO::Scalar( \($options{content}) );
      } else {
        require IO::Scalar::Fake;
        $read_fh = new IO::Scalar::Fake( \($options{content}) );
      }
    }

    for(my $i=0; $i<$computed_size; $i+=$block_size) {
      my $s = ($i+$block_size > $computed_size) ?
        ($computed_size - $i) :
        ($block_size);
      warn "Reading $s" if $DEBUG;
      $read_fh->read($c, $s);
      $crc32 = _crc32($c, $crc32);
      ($out, $status) = $d->deflate($c);
      if($status) {
        confess "Deflate error: $status ".$d->msg;
      }
      $compressed_size+=length($out);
      $self->_print($out);
    }
    ($out, $status) = $d->flush() ;
    if($status) {
      confess "Deflate error: $status";
    }
    $compressed_size+=length($out);
    $self->_print($out);
    $uncompressed_size = $computed_size;
  } elsif($options{Method} eq "store" and ref($options{content})) {
    my $block_size = $self->{block_size};
    my $c;

    # If it's still a filehandle, a loop will be needed.
    for(my $i=0; $i<$computed_size; $i+=$block_size) {
      my $s = ($i+$block_size > $computed_size) ?
        ($computed_size - $i) :
        ($block_size);
      warn "Reading $s" if $DEBUG;
      $options{content}->read($c, $s);
      $self->_print($c);
    }
    # No need for a data descriptor.
  } elsif($options{Method} eq "store") {
    $self->_print($options{content});
    # No need for a data descriptor.
  } else {
    confess;
  }

  if($bit_flag & $SIZE_IN_DATA_DESCRIPTOR) {
    # Then we can do the data descriptor
    $self->_print(_pack_fake("VV".($zip64_needed ? "QQ" : "VV"),
      0x08074b50, # signature, shouldn't be needed. PK 007 008
      $crc32, # crc-32
      $compressed_size, # compressed size
      $uncompressed_size, # uncompressed size
    ));
  }
  #$self->{fh}->flush();
  warn "$compressed_size $uncompressed_size $options{Name}" if $DEBUG;
  my $file_comment = defined($options{file_comment}) ? $options{file_comment} : ""; # 16-bit length
  my $os_version = $options{os_version} || 3; # UNIX

  my $internal_file_attributes = 0;
  $internal_file_attributes |= 1 if $options{internal_file_attributes}{ascii};

  my $nonlocal_extra_fields_packed = "";
  if($zip64_needed) {
    my $zip64_ei_body = "";
    foreach($uncompressed_size, $compressed_size, $initial_offset) {
      $zip64_ei_body.=_pack_fake("Q", $_);
    }
    # I'm ignoring the disk start number completely.
    unshift(@{ $options{ExtraField} },
      pack("S", 0x0001) => $zip64_ei_body
    );
  }
  if($options{ExtraField}) {
    my @ef = @{$options{ExtraField}};
    for(my $i=0; $i<scalar(@ef); $i+=2) {
      $nonlocal_extra_fields_packed.=
        $ef[$i+0].
        pack("S", length($ef[$i+1])).
        $ef[$i+1];
    }
  }

  push @{$self->{central_headers}}, pack("VSSSSSSVVVSSSSSVV",
    0x02014b50, # central file header signature
    ($os_version<<8) | $self->{spec_version}, # version made by
    $self->{spec_version}, # version needed to extract
    $bit_flag, # general purpose bit flag
    $compression_method_n, # compression method
    $dos_time, # last mod file time
    $dos_date, # last mod file date
    $crc32, # crc-32
    ($zip64_needed ? 0xff_ff_ff_ff : $compressed_size), # compressed size
    ($zip64_needed ? 0xff_ff_ff_ff : $uncompressed_size), # uncompressed size
    length($options{Name}), # file name length
    length($nonlocal_extra_fields_packed), # extra field length
    length($file_comment), # file comment length
    0, # disk number start - theoretically in zip64 this can be FFFF with the real value in the zip64 EI
    $internal_file_attributes, # internal file attributes
    $options{ExtAttr}, # external file attributes
    ($zip64_needed ? 0xff_ff_ff_ff : $initial_offset), # relative offset of local header - in zip64, if FFFFFFFF, look in the zip64 EI.
  ).$options{Name}.$nonlocal_extra_fields_packed.$file_comment;
}

=head2 close()

=head2 close($os_version)

=head2 close($os_version, $comment)

Prints all the necessary trailling information and then closes the filehandle.

$os_version will default to 3 (UNIX); in this context it's extremely
likely to be taken as the OS of the system on which this software is
running, however it might be taken as being relevant to the individual
files in the zip content so you may well want this value to be consistent
throughout the zip file. See print_item() above.

$comment is, like in print_item() above, limited to a 16-bit length and
not recommended. In this context, it would be a comment for the whole
zip file.

=cut

# Zip64-compats large numbers. x<2^n => x; else (2^n)-1
sub _z64 {
  my ($bits, $n) = @_;
  if($n < 2**$bits) {
    return $n;
  } else {
    return( (2**$bits) - 1);
  }
}

sub close {
  my ($self, $os_version, $comment) = @_;
  my $initial_offset = $self->{written};

  my @ch = @{$self->{central_headers}};
  my $cdl = 0;
  for(@ch) {
    $self->_print($_);
    $cdl+=length($_);
  }

  $os_version ||= 3; # UNIX

  if($self->{zip64}) {
    my $zip64_eocd_offset = $self->{written};

    # zip64 EOCD
    my $zip64_extensible_data_sector = "";
    $self->_print(_pack_fake("VQSSVVQQQQ", 
      0x06064b50, # zip64 end of central dir signature
      length($zip64_extensible_data_sector) + 4+8+2+2+4+4+8+8+8+8, # size of zip64 end of central directory record
      ($os_version<<8) | $self->{spec_version}, # version made by
      $self->{spec_version}, # version needed to extract
      0, # number of this disk
      0, # number of the disk with the start of the central directory
      scalar(@ch), # total number of entries in the central directory on this disk
      scalar(@ch), # total number of entries in the central directory
      $cdl, # size of the central directory
      $initial_offset, # offset of start of central directory with respect to the starting disk number
    ).$zip64_extensible_data_sector); # zip64 extensible data sector

    # zip64 EOCDL
    $self->_print(_pack_fake("VVQV", 
      0x07064b50, # zip64 end of central dir locator signature
      0, # number of the disk with the start of the zip64 end of central directory
      $zip64_eocd_offset, # relative offset of the zip64 end of central directory record
      1, # total number of disks
    ));
  }

  # Digital signature is not required, but would start 0x05054b50
  my $zip_file_comment = defined($comment) ? $comment : ""; # 16-bit length
  $self->_print(pack("VSSSSVVS", 
    0x06054b50, # end of central dir signature
    0, # number of this disk
    0, # number of the disk with the start of the central directory
    _z64(16, scalar(@ch)), # total number of entries in the central directory on this disk
    _z64(16, scalar(@ch)), # total number of entries in the central directory
    _z64(32, $cdl), # size of the central directory
    _z64(32, $initial_offset), # offset of start of central directory with respect to the starting disk number
    length($zip_file_comment) # .ZIP file comment length
  ).$zip_file_comment);
  close($self->{fh});
  $self->{fh} = undef;
  1;
}

=head1 NOTES

You don't get a DESTROY because that could close the zip file early in children.

=cut

1;
