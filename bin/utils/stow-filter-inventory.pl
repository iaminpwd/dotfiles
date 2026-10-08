#!/usr/bin/env perl
# Use GNU Stow's own ignore matcher so backups match its installed file set.
# NUL-delimited inputs/outputs preserve arbitrary filenames.
use strict;
use warnings;
use Cwd qw(abs_path getcwd);
use File::Basename qw(dirname);
use File::Find ();
use File::Spec;

@ARGV == 8 or die "usage: stow-filter-inventory.pl STOW_DIR PKG HOME SOURCE_PREFIX DIRS FILES OUT_DIRS OUT_FILES\n";
my ($stow_dir, $pkg, $home, $source_prefix, $dirs, $files, $out_dirs, $out_files) = @ARGV;

# GNU Stow can be behind a test-only invocation wrapper. Examine candidates
# on PATH in order and use the first one that provides the actual Stow.pm
# library. A missing or untrusted module fails closed before any user mv.
my @stow_candidates =
  grep { -f $_ && -x $_ } map { "$_/stow" } split /:/, $ENV{PATH} // '';
@stow_candidates or die "GNU Stow executable missing; refusing to move user files\n";
my %seen;
my $loaded = 0;
for my $stow_exe (@stow_candidates) {
  my $real_exe = abs_path($stow_exe) or next;
  next if $seen{$real_exe}++;

  # GNU Stow's generated launcher records its authoritative Perl library
  # location in a literal 'use lib' directive. Read data; do not eval code.
  if (open my $launcher, '<', $real_exe) {
    while (my $line = <$launcher>) {
      if ($line =~ /^\s*use\s+lib\s+["']([^"']+)["']\s*;/) {
        unshift @INC, $1;
      }
    }
    close $launcher;
  }

  my $prefix = dirname(dirname($real_exe));
  unshift @INC, "$prefix/lib/perl5", "$prefix/share/perl5";
  $loaded = eval { require Stow; 1 };
  last if $loaded;

  # Homebrew stores Perl modules under version-specific subdirectories.
  # Scope discovery to the installation's lib/share roots; do not scan /usr.
  for my $root ("$prefix/lib", "$prefix/share") {
    next unless -d $root;
    File::Find::find({
      no_chdir => 1,
      wanted => sub {
        return unless $File::Find::name =~ m{/Stow[.]pm$};
        unshift @INC, dirname($File::Find::name);
      },
    }, $root);
  }
  $loaded = eval { require Stow; 1 };
  last if $loaded;
}
$loaded or die "Cannot load the Perl library used by GNU Stow: $@\n";

my $old_cwd = getcwd();
chdir $home or die "Cannot enter HOME to evaluate Stow ignore rules: $home: $!\n";
local $ENV{HOME} = $home;
my $stow = Stow->new(dir => $stow_dir, target => $home);
# Load Stow's package-specific ignore rules before evaluating paths.
# In particular, the local rule file takes precedence over the user's global
# file, and the compiled regexes are memoized by the Stow Perl library.
$stow->get_ignore_regexps("$stow->{stow_path}/$pkg");

sub is_ignored {
  my ($rel) = @_;
  my @parts = split m{/}, $rel;
  my $path = '';
  for my $part (@parts) {
    $path = length($path) ? "$path/$part" : $part;
    # Checking ancestors is necessary: Stow skips an ignored directory
    # before walking its descendants.
    return 1 if $stow->ignore($stow->{stow_path}, $pkg, $path);
  }
  return 0;
}

sub filter_inventory {
  my ($input, $output) = @_;
  open my $in, '<', $input or die "Cannot read Stow inventory $input: $!\n";
  open my $out, '>', $output or die "Cannot create filtered Stow inventory $output: $!\n";
  binmode $in;
  binmode $out;
  local $/ = "\0";
  while (my $path = <$in>) {
    chomp $path;
    index($path, $source_prefix) == 0
      or die "Unexpected path outside package inventory: $path\n";
    my $rel = substr($path, length($source_prefix));
    length($rel) or die "Empty relative Stow path: $path\n";
    my $ignored = is_ignored($rel);
    next if $ignored;
    print {$out} "$path\0" or die "Cannot write filtered Stow inventory: $!\n";
  }
  close $in or die "Cannot close Stow inventory: $!\n";
  close $out or die "Cannot finish filtered Stow inventory: $!\n";
}

filter_inventory($dirs, $out_dirs);
filter_inventory($files, $out_files);
chdir $old_cwd or die "Cannot restore working directory: $!\n";
