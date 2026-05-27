#!/usr/bin/perl
#
# kevin-mood-ring v0.1.0
# Real Engineering Sentiment Analytics — but actually honest.
#
# Reads your git log and tells you, with math and sass, how miserable
# your dev team is. Pseudo-scientific by design. Free by principle.
#
# Cross-platform: Mac, Linux, Windows (via Strawberry Perl or Git Bash).
# Zero external CPAN dependencies. Pure Perl 5 stdlib.
#
# Kevin Sigmoid Industries — https://github.com/kevin-sigmoid-org
# AGPL-3.0 License. If you run this as a SaaS, give back. Kevin watches.
#

use strict;
use warnings;
use feature 'say';
use utf8;
use Getopt::Long qw(:config bundling no_ignore_case);
use Term::ANSIColor qw(:constants colored);
use POSIX qw(strftime);

# Make Unicode output (emojis, box-drawing) work cleanly cross-platform.
binmode STDOUT, ':encoding(UTF-8)';
binmode STDERR, ':encoding(UTF-8)';

my $VERSION = '0.1.0';

# ---------------------------------------------------------------------------
# OPTIONS
# ---------------------------------------------------------------------------
my %opt = (
    repo             => '.',
    since            => '1 year ago',
    lang             => 'all',
    verbose          => 0,
    color            => 1,
    all_branches     => 0,
    include_deleted  => 0,
);

my $show_help    = 0;
my $show_version = 0;

GetOptions(
    'r|repo=s'          => \$opt{repo},
    's|since=s'         => \$opt{since},
    'l|lang=s'          => \$opt{lang},
    'v|verbose'         => \$opt{verbose},
    'a|all'             => \$opt{all_branches},
    'include-deleted'   => \$opt{include_deleted},
    'no-color'          => sub { $opt{color} = 0; $ENV{ANSI_COLORS_DISABLED} = 1 },
    'h|help'            => \$show_help,
    'V|version'         => \$show_version,
) or die_help();

# --include-deleted implies --all (you cannot ask for ghosts of branches you
# do not look at).
$opt{all_branches} = 1 if $opt{include_deleted};

if ($show_version) {
    say "kevin-mood-ring $VERSION";
    say "Perl $] on $^O";
    say "Kevin Sigmoid Industries — AGPL-3.0 licensed.";
    exit 0;
}

print_help() if $show_help;

# ---------------------------------------------------------------------------
# CORPUS (multilingual despair)
# ---------------------------------------------------------------------------
# Note: these are heuristics, not science. They are good enough.
my %SWEARS = (
    en => qr/\b(?:fuck|fck|damn|wtf|shit|crap|asdf|ugh|argh|nope|broken|hate)\b/i,
    fr => qr/\b(?:putain|merde|chiant|naze|nope|wtf|fou|n[\xE9e]importe)\b/i,
    de => qr/\b(?:scheisse|verdammt|mist|wtf|kacke)\b/i,
    es => qr/\b(?:mierda|joder|wtf)\b/i,
);

my $DESPAIR_TITLES = qr/^(?:wip|fix|fixes|fixed|asdf|please\s+work|ugh|last\s+try|nope|trying\s+again|test|tests|try|tmp|temp|todo|hack|hacky|quickfix|hotfix|please|finally|tweak|adjustments?|stuff|changes?|update|updates)$/i;

my $DREAD_RX     = qr/[\?]{2,}|[\.]{3,}|!{2,}/;
my $YELLING_RX   = qr/^[A-Z\s\d_!?\.\-]{8,}$/; # ALL CAPS titles
my $RAGE_RX      = qr/(?:!!!|\?\?\?|why\s+god|this\s+is\s+broken|i\s+give\s+up|kill\s+me)/i;

# ---------------------------------------------------------------------------
# FETCH DATA
# ---------------------------------------------------------------------------
banner();

my $repo  = $opt{repo};
my $since = $opt{since};

# Sanity: is this a git repo?
my $git_check = qx{git -C "$repo" rev-parse --is-inside-work-tree 2>&1};
unless ($git_check && $git_check =~ /^true/) {
    err("Not a git repository: $repo");
    err("Kevin requires a git repo. Kevin will not pretend otherwise.");
    exit 2;
}

# Fetch commits. Format: SHA|ISO_DATE|AUTHOR|SUBJECT
# We use unit-separator (\x1F) to safely handle pipes in subjects.
my $sep        = "\x1F";
my @scope_flags;
push @scope_flags, '--all'    if $opt{all_branches};
push @scope_flags, '--reflog' if $opt{include_deleted};
my $scope_flag = join(' ', @scope_flags);
# Deduplicate when --reflog is set: the same commit can appear via multiple
# refs (current branch + reflog entry). Kevin will not count a commit twice.
my %seen;
my @raw = grep { my ($s) = split /\Q$sep/, $_, 2; defined $s && !$seen{$s}++ }
          split /\n/, qx{git -C "$repo" log $scope_flag --since="$since" --pretty=format:"%h${sep}%aI${sep}%an${sep}%s" 2>&1};
my $total  = scalar @raw;

if ($total == 0) {
    warn_say("No commits found since '$since' in $repo.");
    warn_say("Either your team is on PTO, or you mistyped the date.");
    warn_say("Kevin assumes the former. Kevin is wrong.");
    exit 0;
}

# ---------------------------------------------------------------------------
# ANALYSE
# ---------------------------------------------------------------------------
my $swears       = 0;
my $despair      = 0;
my $dread        = 0;
my $yelling      = 0;
my $rage         = 0;
my $friday_pm    = 0;
my $friday_total = 0;
my $sunday_late  = 0;
my $coauth_boost = 0;
my %author_count;
my %day_count;
my @per_commit_log;

for my $line (@raw) {
    my ($sha, $iso, $author, $msg) = split /\Q$sep/, $line, 4;
    next unless defined $msg;

    # Date parsing (we only need the day-of-week and hour)
    my ($Y,$M,$D,$h) = $iso =~ /^(\d{4})-(\d{2})-(\d{2})T(\d{2})/;
    next unless defined $h;
    # mktime returns a scalar epoch; we then re-localtime to get wday.
    # (mktime alone does not expose day-of-week in scalar form.)
    my $epoch = POSIX::mktime(0, 0, $h + 0, $D + 0, $M - 1, $Y - 1900);
    next unless defined $epoch && $epoch >= 0;
    my $dow  = (localtime($epoch))[6]; # 0 = Sunday ... 6 = Saturday
    my $hour = $h + 0;

    $author_count{$author}++;
    $day_count{$dow}++;

    my $hit_swear   = 0;
    my $hit_despair = ($msg =~ $DESPAIR_TITLES) ? 1 : 0;
    my $hit_dread   = ($msg =~ $DREAD_RX)       ? 1 : 0;
    my $hit_yelling = ($msg =~ $YELLING_RX)     ? 1 : 0;
    my $hit_rage    = ($msg =~ $RAGE_RX)        ? 1 : 0;

    for my $lang (lang_keys($opt{lang})) {
        if ($msg =~ $SWEARS{$lang}) { $hit_swear = 1; last }
    }

    $swears  += $hit_swear;
    $despair += $hit_despair;
    $dread   += $hit_dread;
    $yelling += $hit_yelling;
    $rage    += $hit_rage;

    # Friday PM (16h-20h on Friday = dow == 5)
    if ($dow == 5) {
        $friday_total++;
        $friday_pm++ if $hour >= 16 && $hour <= 20;
    }

    # Sunday after 22h (= the cry for help)
    $sunday_late++ if $dow == 0 && $hour >= 22;

    if ($opt{verbose}) {
        my @flags;
        push @flags, 'SWEAR'   if $hit_swear;
        push @flags, 'DESPAIR' if $hit_despair;
        push @flags, 'DREAD'   if $hit_dread;
        push @flags, 'YELLING' if $hit_yelling;
        push @flags, 'RAGE'    if $hit_rage;
        push @per_commit_log, sprintf('%s  %s  %-20s  %s  %s',
            $sha, substr($iso, 0, 16), substr($author, 0, 20),
            (@flags ? "[" . join(',', @flags) . "]" : ""),
            substr($msg, 0, 50));
    }
}

# Co-authored-by boost: look at full commit log for "Co-authored-by"
my $coauth_lines = qx{git -C "$repo" log $scope_flag --since="$since" 2>&1};
$coauth_boost = () = $coauth_lines =~ /Co-authored-by:/gi;

# ---------------------------------------------------------------------------
# SCORES
# ---------------------------------------------------------------------------
my $mood_raw      = 100 - int( (($swears * 3) + ($despair * 2) + $dread + $rage * 4) * 100 / max(1, $total) );
my $mood          = clamp($mood_raw + int($coauth_boost * 100 / max(1, $total * 2)), 0, 100);

my $despair_pct   = pct($despair, $total);
my $friday_coef   = pct($friday_pm, max(1, $friday_total));
my $sunday_pct    = pct($sunday_late, $total);
my $dread_pct     = pct($dread + $rage, $total);

# ---------------------------------------------------------------------------
# OUTPUT
# ---------------------------------------------------------------------------
say "";
my $scope_label = $opt{include_deleted} ? 'all branches + reflog ghosts'
                : $opt{all_branches}   ? 'all branches'
                :                        'current branch only';

header("🧠 ENGINEERING MOOD REPORT");
ruler();
printf "  Repo:            %s\n",   $opt{repo};
printf "  Window:          %s\n",   $opt{since};
printf "  Scope:           %s\n",   $scope_label;
printf "  Commits scanned: %d\n",   $total;
printf "  Languages:       %s\n",   join(', ', lang_keys($opt{lang}));
printf "  Authors:         %d\n",   scalar keys %author_count;
ruler();
say "";

bar_line("OVERALL MOOD",                $mood,        mood_emoji($mood));
bar_line("DESPAIR INDEX",               $despair_pct, severity_emoji($despair_pct));
bar_line("FRIDAY-AFTERNOON COEFFICIENT", $friday_coef, severity_emoji($friday_coef));
bar_line("SUNDAY-NIGHT TRAUMA",         $sunday_pct,  severity_emoji($sunday_pct));
bar_line("EXISTENTIAL DREAD",           $dread_pct,   severity_emoji($dread_pct));

say "";
ruler();
header("🩺 DIAGNOSIS");
ruler();
diagnose($mood, $despair_pct, $friday_coef, $sunday_pct, $dread_pct, $total, $swears, $coauth_boost);

say "";
ruler();
header("📜 RECOMMENDED INTERVENTIONS");
ruler();
recommend($mood, $friday_coef, $sunday_pct);

if ($opt{verbose} && @per_commit_log) {
    say "";
    ruler();
    header("🔍 PER-COMMIT FORENSICS");
    ruler();
    say "  SHA       DATE              AUTHOR                FLAGS               SUBJECT";
    for my $row (@per_commit_log) {
        say "  $row";
    }
}

say "";
ruler();
printf "  Kevin Sigmoid Industries · v%s · AGPL-3.0 · %s\n", $VERSION, signature();
say "";

exit 0;

# ===========================================================================
# SUBROUTINES
# ===========================================================================

sub lang_keys {
    my ($l) = @_;
    return keys %SWEARS if $l eq 'all';
    return ($l) if exists $SWEARS{$l};
    err("Unknown language: $l. Falling back to 'all'.");
    return keys %SWEARS;
}

sub pct  { my ($n,$tot) = @_; return int($n * 100 / max(1, $tot)); }
sub max  { my ($a,$b) = @_; return $a > $b ? $a : $b; }
sub clamp { my ($v,$lo,$hi) = @_; $v < $lo ? $lo : $v > $hi ? $hi : $v; }

sub bar {
    my ($n) = @_;
    my $filled = int($n / 10);
    return ("\x{2588}" x $filled) . ("\x{2591}" x (10 - $filled));
}

sub bar_line {
    my ($label, $val, $emoji) = @_;
    my $color = $val >= 70 ? 'red' : $val >= 40 ? 'yellow' : 'green';
    # Mood is inverted: higher = better
    if ($label eq 'OVERALL MOOD') {
        $color = $val < 30 ? 'red' : $val < 60 ? 'yellow' : 'green';
    }
    printf "  %-32s %s  %3d%% %s\n",
        $label, colored([$color], bar($val)), $val, $emoji // '';
}

sub mood_emoji {
    my $n = shift;
    return "\x{1FAA6}" if $n < 20;   # 🪦 grave
    return "\x{1F480}" if $n < 40;   # 💀
    return "\x{1F622}" if $n < 60;   # 😢
    return "\x{1F610}" if $n < 80;   # 😐
    return "\x{1F642}";              # 🙂
}

sub severity_emoji {
    my $n = shift;
    return "\x{1F525}" if $n >= 80;  # 🔥
    return "\x{26A0}\x{FE0F}" if $n >= 60;  # ⚠️
    return "";
}

sub diagnose {
    my ($mood, $des, $fri, $sun, $dread, $tot, $swears, $coauth) = @_;
    say "";
    if ($mood < 20) {
        say "  Your team writes 'fix' more often than they fix things.";
        say "  Statistical despair has reached terminal velocity.";
        say "  Kevin recommends opening a window. Outside. Not yours.";
    } elsif ($mood < 40) {
        say "  Your team is functioning. Barely. Kevin can hear them sighing.";
        say "  $des% of commits are coping mechanisms disguised as work.";
        say "  This is normal in Q4. It is May.";
    } elsif ($mood < 60) {
        say "  Your team has reached the 'professional resignation' baseline.";
        say "  They no longer hope, but they no longer panic. This is growth.";
        say "  Kevin acknowledges the maturity.";
    } elsif ($mood < 80) {
        say "  Your team appears functional and possibly even content.";
        say "  Kevin is suspicious. Are they lying in the commits?";
        say "  Check their Slack DMs to be sure.";
    } else {
        say "  Suspiciously high mood detected. Either your team is new,";
        say "  or someone is performance-reviewing their own git log.";
        say "  Kevin will not vouch for these numbers.";
    }

    say "";
    say "  KEY OBSERVATIONS:" if $fri >= 50 || $sun >= 5 || $coauth > 0 || $swears > 5;
    say "  - Friday afternoons are $fri% degraded. Cancel the Friday standup." if $fri >= 50;
    say "  - $sun% of commits land on Sunday after 22h. This is a cry for help." if $sun >= 5;
    say "  - $coauth commits are co-authored. Pair-programming detected. Mood +."  if $coauth > 0;
    say "  - $swears swear words in commit messages. Refreshing honesty." if $swears > 5;
}

sub recommend {
    my ($mood, $fri, $sun) = @_;
    say "";
    if ($mood < 30) {
        say "  1. Hire one (1) additional developer. Immediately.";
        say "  2. Cancel all standups for two weeks. Observe.";
        say "  3. Buy them coffee. Real coffee. Not the office one.";
        say "  4. Therapy. Individual or collective, Kevin does not judge.";
    } elsif ($mood < 60) {
        say "  1. Skip one meeting per week. Replace with focused work.";
        say "  2. Audit your incident response process. Trauma adds up.";
        say "  3. Buy snacks. Actually good snacks. Not the granola bars.";
    } else {
        say "  1. Keep doing what you are doing.";
        say "  2. But not too much. Hubris is a soft skill.";
        say "  3. Maybe write a blog post. Kevin will not read it.";
    }
    say "  4. Stop committing on Sundays. Kevin sees you." if $sun >= 5;
    say "  5. Cancel Friday standup. Friday afternoon is not for ceremonies." if $fri >= 50;
}

sub signature {
    my @sigs = (
        "Kevin validated this.",
        "Kevin has opinions.",
        "Kevin remains unconvinced.",
        "Kevin acknowledges your effort.",
        "Kevin has seen worse. Not by much.",
        "Kevin reminds you he is not a therapist.",
    );
    return $sigs[ int(rand @sigs) ];
}

sub banner {
    return unless $opt{color};
    print BOLD, BRIGHT_MAGENTA;
    print q{
    _  __         _         __  __                 _   ___ _
   | |/ /_____ __(_)_ _    |  \/  |___  ___  __ _ | | | _ (_)_ _  __ _
   | ' </ -_) V / | ' \   | |\/| / _ \/ _ \/ _` || | |   / | ' \/ _` |
   |_|\_\___|\_/|_|_||_|  |_|  |_\___/\___/\__,_||_| |_|_\_|_||_\__, |
                                                                |___/
};
    print RESET;
}

sub header { say BOLD, BRIGHT_CYAN, "  ", $_[0], RESET; }
sub ruler  { say "  ", "\x{2500}" x 64; }
sub err       { say STDERR colored(['red'], "  ERROR: " . $_[0]); }
sub warn_say  { say colored(['yellow'], "  WARN: " . $_[0]); }

# ===========================================================================
# HELP
# ===========================================================================

sub die_help { print_help(); exit 2 }

sub print_help {
    my $h = << "END_HELP";
${\BOLD}${\BRIGHT_MAGENTA}kevin-mood-ring${\RESET}  v$VERSION
Real Engineering Sentiment Analytics${\BRIGHT_CYAN}\x{2122}${\RESET}  ${\YELLOW}— but actually honest, free, and offline.${\RESET}

Reads your git log. Tells you, with math and sass, how miserable your dev
team is. Kevin does not believe in sentiment analysis. Kevin believes in
git log. Kevin reads what your team types when they think no one is reading.

${\BOLD}USAGE${\RESET}
  perl mood-ring.pl [OPTIONS]

${\BOLD}OPTIONS${\RESET}
  ${\GREEN}-r${\RESET}, ${\GREEN}--repo${\RESET}  ${\BRIGHT_BLACK}PATH${\RESET}      Path to a git repository.
                        ${\BRIGHT_BLACK}Default: '.' (the one you stand in. Kevin will judge it.)${\RESET}

  ${\GREEN}-s${\RESET}, ${\GREEN}--since${\RESET} ${\BRIGHT_BLACK}DATE${\RESET}     How far back to look.
                        ${\BRIGHT_BLACK}Accepts anything 'git log --since' eats: '2 weeks ago',${\RESET}
                        ${\BRIGHT_BLACK}'2026-01-01', 'last monday'. Default: '1 year ago'.${\RESET}

  ${\GREEN}-l${\RESET}, ${\GREEN}--lang${\RESET}  ${\BRIGHT_BLACK}LANG${\RESET}     Language used for swear-word detection.
                        ${\BRIGHT_BLACK}One of: en, fr, de, es, all. Default: all. Kevin is${\RESET}
                        ${\BRIGHT_BLACK}very inclusive about despair.${\RESET}

  ${\GREEN}-v${\RESET}, ${\GREEN}--verbose${\RESET}         Show per-commit forensics.
                        ${\BRIGHT_BLACK}Warning: may reveal things about your team you did not${\RESET}
                        ${\BRIGHT_BLACK}want to know.${\RESET}

  ${\GREEN}-a${\RESET}, ${\GREEN}--all${\RESET}             Scan all branches, not just the current one.
                        ${\BRIGHT_BLACK}Default is current branch only. With --all, Kevin reads${\RESET}
                        ${\BRIGHT_BLACK}your messy feature branches too. Reality.${\RESET}

      ${\GREEN}--include-deleted${\RESET} Also include commits from deleted branches still
                        in the local reflog (implies --all). Kevin does not
                        ${\BRIGHT_BLACK}chase ghosts on GitHub — Kevin only reads what your git${\RESET}
                        ${\BRIGHT_BLACK}repo still remembers. Garbage-collected commits remain${\RESET}
                        ${\BRIGHT_BLACK}lost. Kevin has principles.${\RESET}

      ${\GREEN}--no-color${\RESET}        Disable ANSI colors.
                        ${\BRIGHT_BLACK}For environments where joy must be suppressed (CI,${\RESET}
                        ${\BRIGHT_BLACK}Jenkins, hostile pipelines, your colleague's terminal).${\RESET}

  ${\GREEN}-h${\RESET}, ${\GREEN}--help${\RESET}            Show this help. You are here.

  ${\GREEN}-V${\RESET}, ${\GREEN}--version${\RESET}         Print version and exit. Not very satisfying.

${\BOLD}EXAMPLES${\RESET}
  ${\BRIGHT_BLACK}# Analyse the current repo, last year, all languages:${\RESET}
  ${\BRIGHT_GREEN}\$${\RESET} perl mood-ring.pl

  ${\BRIGHT_BLACK}# Look only at the last 3 months on a specific repo:${\RESET}
  ${\BRIGHT_GREEN}\$${\RESET} perl mood-ring.pl --repo ../my-shame --since '3 months ago'

  ${\BRIGHT_BLACK}# Detect only French despair (regional crisis mode):${\RESET}
  ${\BRIGHT_GREEN}\$${\RESET} perl mood-ring.pl --lang fr

  ${\BRIGHT_BLACK}# All branches, including the embarrassing feature ones:${\RESET}
  ${\BRIGHT_GREEN}\$${\RESET} perl mood-ring.pl --all

  ${\BRIGHT_BLACK}# Also include commits from deleted branches (local reflog):${\RESET}
  ${\BRIGHT_GREEN}\$${\RESET} perl mood-ring.pl --include-deleted

  ${\BRIGHT_BLACK}# Verbose forensics, no color, ready for that anonymous tip:${\RESET}
  ${\BRIGHT_GREEN}\$${\RESET} perl mood-ring.pl --verbose --no-color > engineering-distress.txt

${\BOLD}OUTPUT GUIDE${\RESET}
  ${\BRIGHT_CYAN}OVERALL MOOD${\RESET}                   0\x{2013}100. Higher is better. 80+ is suspicious.
  ${\BRIGHT_CYAN}DESPAIR INDEX${\RESET}                  Density of 'wip' / 'fix' / 'asdf' / 'please work'.
  ${\BRIGHT_CYAN}FRIDAY-AFTERNOON COEFFICIENT${\RESET}   How fast quality degrades 16:00\x{2013}20:00 on Fridays.
  ${\BRIGHT_CYAN}SUNDAY-NIGHT TRAUMA${\RESET}            Commits after 22:00 on Sundays. The cry for help.
  ${\BRIGHT_CYAN}EXISTENTIAL DREAD${\RESET}              Question marks, ellipses, ALL CAPS rage.

${\BOLD}PHILOSOPHY${\RESET}
  Kevin does not believe in sentiment analysis.
  Kevin believes in git log.
  Kevin will not pretend to read between the lines. Kevin reads the lines.

${\BOLD}WARRANTY${\RESET}
  None. Kevin Sigmoid Industries assumes no responsibility for any HR
  conversations that may result from sharing this report.

${\BOLD}LICENSE${\RESET}
  AGPL-3.0. Use it. Fork it. Inflict it on others.
  If you run a modified version as a SaaS, you owe your users the source.

${\BOLD}HOMEPAGE${\RESET}
  https://github.com/kevin-sigmoid-org/commit-mood-ring

${\BRIGHT_BLACK}Kevin validated this.${\RESET}

END_HELP
    print $h;
    exit 0 if $show_help;
}
