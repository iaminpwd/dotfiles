#!/usr/bin/env perl
# Use GNU Stow's own ignore matcher so backups match its installed file set.
# NUL-delimited inputs/outputs preserve arbitrary filenames.
use strict;
use warnings;
use Cwd qw(abs_path getcwd);
use File::Basename qw(dirname);
use File::Spec;

@ARGV == 8 or die "usage: stow-filter-inventory.pl STOW_DIR PKG HOME SOURCE_PREFIX DIRS FILES OUT_DIRS OUT_FILES\n";
my ($stow_dir, $pkg, $home, $source_prefix, $dirs, $files, $out_dirs, $out_files) = @ARGV;

# GNU Stow may install its Perl modules beside the resolved stow executable
# (particularly Homebrew), rather than in the system Perl's default @INC.
my ($stow_exe) = grep { -f $_ && -x $_ } map { "$_/stow" } split /:/, $ENV{PATH} // '';
defined $stow_exe or die "GNU Stow executable missing; refusing to move user files\n";
my $real_exe = abs_path($stow_exe)
  or die "Cannot resolve GNU Stow executable: $stow_exe\n";
my $prefix = dirname(dirname($real_exe));
unshift @INC, "$prefix/lib/perl5", "$prefix/share/perl5";
require Stow;

my $old_cwd = getcwd();
chdir $home or die "Cannot enter HOME to evaluate Stow ignore rules: $home: $!\n";
local $ENV{HOME} = $home;
my $stow = Stow->new(dir => $stow_dir, target => $home);

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
    next if is_ignored($rel);
    print {$out} "$path\0" or die "Cannot write filtered Stow inventory: $!\n";
  }
  close $in or die "Cannot close Stow inventory: $!\n";
  close $out or die "Cannot finish filtered Stow inventory: $!\n";
}

filter_inventory($dirs, $out_dirs);
filter_inventory($files, $out_files);
chdir $old_cwd or die "Cannot restore working directory: $!\n";
