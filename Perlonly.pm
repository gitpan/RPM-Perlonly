# Copyright (c) 2001, Troels Liebe Bentsen. All rights reserved.  This
# program is free software; you can redistribute it and/or modify it under
# the same terms of LGPL.

package RPM::Perlonly;
use vars '$VERSION';
$VERSION = '1.0';

use strict;
use RPM::Tagtable;

sub TIEHASH   # during tie()
{
	my $RPM_HEADER_MAGIC = chr(0x8e).chr(0xad).chr(0xe8);
	my $RPM_FILE_MAGIC   = chr(0xed).chr(0xab).chr(0xee).chr(0xdb);
	my $buff;
	
	my ($class_name, $filename) = @_;
	my $self = bless { hash => {}, }, $class_name;
	
	if (!defined($filename) or !open(RPMFILE, "<$filename")) { return 0; }
	
	binmode(RPMFILE);
	
	# Read rpm lead
	read(RPMFILE, $buff, 96);
	( $self->{'hash'}->{'LEAD_MAGIC'},		# unsigned char[4], í«îÛ == rpm
	  $self->{'hash'}->{'LEAD_MAJOR'},		# unsigned char, 3 == rpm version 3.x
	  $self->{'hash'}->{'LEAD_MINOR'},		# unsigned char, 0 == rpm version x.0
	  $self->{'hash'}->{'LEAD_TYPE'},		# short(int16), 0 == binary, 1 == source
	  $self->{'hash'}->{'LEAD_ARCHNUM'},		# short(int16), 1 == i386
	  $self->{'hash'}->{'LEAD_NAME'},		# char[66], rpm name
	  $self->{'hash'}->{'LEAD_OSNUM'},		# short(int16), 1 == Linux
	  $self->{'hash'}->{'LEAD_SIGNATURETYPE'},	# short(int16), 1280 == rpm 4.0
	  $self->{'hash'}->{'LEAD_RESERVED'}		# char[16] future expansion
	) = unpack("a4CCssA66ssA16", $buff);
	# DEBUG:
	# foreach my $var (keys %{$self->{'hash'}}) { print "$self->{'hash'}->{$var}\n"; } exit;
	
	if (!$self->{'hash'}->{'LEAD_MAGIC'} eq $RPM_FILE_MAGIC) { return 0; }
	
	for (my $header_num=1; $header_num < 3; $header_num++) {
		# DEBUG:
		# print "hlead:".tell(RPMFILE)."\n";
		
		# Read lead of the headers
		read(RPMFILE, $buff, 16);
		
		# DEBUG:
		#rint "hlead:".tell(RPMFILE)."\n";
		
		my ($header_magic, $header_version, $header_reserved, $header_entries, $header_size) = unpack("a3CNNN", $buff);
		
		# DEBUG:
		#print "$header_magic, $header_version, $header_reserved, $header_entries, $header_size\n"; next;
		#read(RPMFILE, $buff, 2200, 0); print "header magic:".index($buff, $RPM_HEADER_MAGIC, 256)."\n"; exit;	
		
		if ($header_magic eq $RPM_HEADER_MAGIC) { # RPM_HEADER_MAGIC
			# Read the record structure.
			my $record;
			read(RPMFILE, $record, 16*$header_entries);	
				
			# Read the tag structure, pad to a multiplyer of 8 if it's the first header.
			if ($header_num == 1) {
				# DEBUG:
				#print "Offset 1: $header_size, ".tell(RPMFILE)."\n";
				if (($header_size % 8) == 0) {
					read(RPMFILE, $buff, $header_size);
				}
				else {
					read(RPMFILE, $buff, $header_size+(8-($header_size % 8)));
				}
			} 
			else {
				# DEBUG:
				#print "Offset 2:".tell(RPMFILE)."\n";
				read(RPMFILE, $buff, $header_size);
			}

			for (my $record_num=0; $record_num < $header_entries; $record_num++) { # RECORD LOOP
				my ($tag, $type, $offset, $count) = unpack("NNNN", substr($record, $record_num*16, 16));
				my @value;
				
				# 10x if signature header.
				if ($header_num == 1) { $tag = $tag*10; }
					
				# Unknown tag
				if (!defined($header_tags{$tag})) { 
					print "Unknown $tag, $type\n"; next; 
				}
				# Null type
				elsif ($type == 0) { 
					@value = ('');
				}
				# Char type
				elsif ($type == 1) {
					print "Char $count $header_tags{$tag}{'TAGNAME'}\n";
					#for (my $i=0; $i < $count; $i++) {
					#push(@value, substr($buff, $offset, $count));
					#	$header_info{$record}{'offset'} += $count;
					#}
				}
				# int8
				elsif ($type == 2) { 
					@value = unpack("C*", substr($buff, $offset, 1*$count)); $offset = 1*$count;
				}
				# int16
				elsif ($type == 3) { 
					@value = unpack("n*", substr($buff, $offset, 2*$count)); $offset = 2*$count;
				} 				 
					# int32
				elsif ($type == 4) { 
					@value = unpack("N*", substr($buff, $offset, 4*$count)); $offset = 4*$count;
				} 				 
				# int64
				elsif ($type == 5) { 
					print "Int64(Not supported) $count $header_tags{$tag}{'TAGNAME'}\n";
					#@value = unpack("N*", substr($buff, $offset, 4*$count)); $offset = 4*$count;
				}
				# String, String array, I18N string array
				elsif ($type == 6 or $type == 8 or $type == 9) {
					for(my $i=0;$i<$count;$i++) {
						my $length = index($buff, "\0", $offset)-$offset;
						push(@value, substr($buff, $offset, $length));
						$offset += $length+1;
					}
				} 
	  			# bin
				elsif ($type == 7) { 
					#print "Bin $count $tags{$tag}{'TAGNAME'}\n";
					$value[0] = substr($buff, $offset, $count);
				}
				# Find out if it's an array type or not.
				if (defined($header_tags{$tag}{'TYPE'}) and $header_tags{$tag}{'TYPE'} == 1) {
					@{$self->{'hash'}->{$header_tags{$tag}{'TAGNAME'}}} =  @value;
				}
				else {
					$self->{'hash'}->{$header_tags{$tag}{'TAGNAME'}} = $value[0];
				}
			} # RECORD LOOP	
		} # HEADER LOOP
	}
	
	# Save package(cpio.gz) location.
	$self->{'hash'}->{'PACKAGE_OFFSET'} = tell(RPMFILE);
	close(RPMFILE);

	# Make old packages look like new ones.
	if (defined($self->{'hash'}->{'FILENAMES'})) {
		my $count = 0;
		my %quick_dirnames;
		foreach my $file (@{$self->{'hash'}->{'FILENAMES'}}) {
			$file =~ /(.*\/)(.*$)/;
			if (!defined($quick_dirnames{$1})) {
				push(@{$self->{'hash'}->{'DIRNAMES'}}, $1);
				$quick_dirnames{$1} = $count++;
			}
			push(@{$self->{'hash'}->{'BASENAMES'}}, $2);
			push(@{$self->{'hash'}->{'DIRINDEXES'}}, $quick_dirnames{$1});		
		}
		delete($self->{'hash'}->{'FILENAMES'});
	}

	# Wait I can beat it, a package sould also provide is's own name, sish (and only once). 
	my %quick_provides = map {$_ => 1} @{$self->{'hash'}->{'PROVIDENAME'}};
	my %quick_provideflags = map {$_ => 1} @{$self->{'hash'}->{'PROVIDEFLAGS'}};
	my %quick_provideversion = map {$_ => 1} @{$self->{'hash'}->{'PROVIDEVERSION'}};
		
	if (!defined($quick_provides{$self->{'hash'}->{'NAME'}}) and !defined($quick_provideflags{8}) and !defined($quick_provideversion{$self->{'hash'}->{'VERSION'}})) {
		push(@{$self->{'hash'}->{'PROVIDENAME'}}, $self->{'hash'}->{'NAME'});
		push(@{$self->{'hash'}->{'PROVIDEFLAGS'}}, 8);
		push(@{$self->{'hash'}->{'PROVIDEVERSION'}}, $self->{'hash'}->{'VERSION'}.'-'.$self->{'hash'}->{'RELEASE'});
	}
	
	
	
	# FILEVERIFYFLAGS is signed
	if ($self->{'hash'}->{'FILEVERIFYFLAGS'}) {
		for(my $i=0;$i<int(@{$self->{'hash'}->{'FILEVERIFYFLAGS'}}); $i++) {
			my $val = @{$self->{'hash'}->{'FILEVERIFYFLAGS'}}[$i];
			if (int($val) == $val && $val >= 2147483648 && $val <= 4294967295) { 
				@{$self->{'hash'}->{'FILEVERIFYFLAGS'}}[$i] -= 4294967296;
			}
		}
	}
		
	# Lets handel the SIGNATURE, this does not work, fix it please.
	if (defined($self->{'hash'}->{'SIGNATURE_MD5'})) {
		$self->{'hash'}->{'SIGNATURE_MD5'} = unpack("H*", $self->{'hash'}->{'SIGNATURE_MD5'});
	}

	# Old stuff, so it can be a drop in replacement for RPM::HEADERS.
	if (defined($self->{'hash'}->{'EPOCH'})) {
		$self->{'hash'}->{'SERIAL'} = $self->{'hash'}->{'EPOCH'};
	}

	if (defined($self->{'hash'}->{'LICENSE'})) {
		$self->{'hash'}->{'COPYRIGHT'} = $self->{'hash'}->{'LICENSE'};
	}
	
	if (defined($self->{'hash'}->{'PROVIDENAME'})) {
		$self->{'hash'}->{'PROVIDES'} = $self->{'hash'}->{'PROVIDENAME'};
	}
	
	if (defined($self->{'hash'}->{'OBSOLETENAME'})) {
		$self->{'hash'}->{'OBSOLETES'} = $self->{'hash'}->{'OBSOLETENAME'};
	}
	
	return $self;
}

sub FETCH     # during $a = $ht{something};
{
	my ($self, $key) = @_;
	return $self->{hash}->{$key};
}

sub STORE     # during $ht{something} = $a;
{
	my ($self, $key, $val) = @_;
	$self->{hash}->{$key} = $val;
}

sub DELETE    # during delete $ht{something}
{
	my ($self, $key) = @_;
	delete $self->{hash}->{$key};
}

sub CLEAR     # during %h = ();
{
	my ($self) = @_;
	$self->{hash} = {};
	();
}

sub EXISTS    # during if (exists $h{something}) { ... }
{
	my ($self, $key) = @_;
	return exists $self->{hash}->{$key};
}

sub FIRSTKEY  # at the beginning of foreach (keys %h) { ... }
{
	my ($self) = @_;
	each %{$self->{hash}};
}

sub NEXTKEY   # during foreach()
{
	my ($self) = @_;
	each %{$self->{hash}};
}

sub DESTROY   # well, when the hash gets destroyed
{
	# do nothing here
}

=head1 NAME

RPM::Perlonly - a perl only implementaion of a RPM header reader.

=head1 SYNOPSIS

	use RPM::Perlonly;
	tie my %rpm, "RPM::Perlonly", "rpm-4.0-1-i586.rpm" or die "Problem, could not open rpm";
	print $rpm{'NAME'};

=head1 DESCRIPTION

Perl-RPM-Perlonly is a clone of RPM::Header written in only perl, so it provides
a way to read a rpm package on systems where rpm is not installed. Perl-RPM-Perlonly
can used as a drop in replacement for RPM::Header, if needed also the other way 
round.

The interface is a tied-hash, there are some tags provided by RPM::Perlonly but not
avalible in RPM::Header, a list is provided here:

head1 AUTHOR

Copyright (c) 2001, Troels Liebe Bentsen. All rights reserved.  This
program is free software; you can redistribute it and/or modify it under
the same terms of LGPL.

=cut

1;
__END__
