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

# GNU Stow may install its Perl modules beside the resolved stow executable
# (particularly Homebrew), rather than in the system Perl's default @INC.
my ($stow_exe) = grep { -f $_ && -x $_ } map { "$_/stow" } split /:/, $ENV{PATH} // '';
defined $stow_exe or die "GNU Stow executable missing; refusing to move user files\n";
my $real_exe = abs_path($stow_exe)
  or die "Cannot resolve GNU Stow executable: $stow_exe\n";
# GNU Stow's generated CLI has the authoritative Perl module path in a
# literal "use lib" declaration (from @USE_LIB_PMDIR@ in stow.in).
# Read it as data; do not execute/eval arbitrary code from the launcher.
open my $launcher, '<', $real_exe or die "Cannot inspect GNU Stow launcher: $!\n";
while (my $line = <$launcher>) {
  if ($line =~ /^\s*use\s+lib\s+["']([^"']+)["']\s*;/) {
    unshift @INC, $1;
  }
}
close $launcher;
my $prefix = dirname(dirname($real_exe));
unshift @INC, "$prefix/lib/perl5", "$prefix/share/perl5";
# Homebrew installs Stow.pm under a Perl-versioned subdirectory of its
# Cellar formula prefix; the path varies across system Perl versions.
# Search only this small formula's lib/share dirs, never the whole /usr tree.
my $loaded = eval { require Stow; 1 };
if (!$loaded) {
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
  eval { require Stow; 1 }
    or die "Cannot load the Perl library used by GNU Stow: $@\n";
}

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
