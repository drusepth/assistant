#!/usr/bin/env ruby
# Verifies config/starter_feeds.opml against the live web (D-hobby-feeds §7.1).
#
# The starter list ships in the repo, so it rots silently: a publisher moves
# a feed, drops RSS, or puts it behind a redirect to somebody else's
# aggregator, and the shelf keeps offering it. A starter that 404s in a
# brand-new account is worse than one we never offered, which is why this is
# wired into CI (.github/workflows/starter-feeds.yml) rather than left as a
# thing somebody remembers to run:
#
#   bin/rails runner script/check_starter_feeds.rb
#   bin/rails runner script/check_starter_feeds.rb --strict     # moves fail too
#   bin/rails runner script/check_starter_feeds.rb --jobs 4
#
# Reports one line per feed: OK, MOVED (with the address it settled on — put
# that in the file), or the failure. Exits non-zero when anything failed, so
# a red run is a list that needs editing.
#
# Two things keep this honest rather than flaky. Every failure is retried
# once after a pause, because one timeout out of three hundred fetches
# is weather, not a dead feed. And the pool never runs two fetches against
# the same host at once — this list multiplies by every self-hoster who ticks
# it, and a checker that hammers a publisher is the opposite of the politeness
# the reader is built on.
require "net/http"

strict = ARGV.delete("--strict")
jobs = (ARGV.include?("--jobs") ? ARGV[ARGV.index("--jobs") + 1].to_i : 6).clamp(1, 12)
RETRY_PAUSE = 3

entries = Feeds::Starters.reload!.entries
abort "No entries in #{Feeds::Starters.path}" if entries.empty?

folders = entries.map(&:folder).uniq.size
puts "Checking #{entries.size} starter feeds across #{folders} topics (#{jobs} at a time)…\n\n"

Outcome = Struct.new(:entry, :status, :detail)

def check(entry)
  page = Web::Fetch.raw(entry.url, headers: { "Accept" => Feeds::Discover::ACCEPT },
    max_bytes: Feeds::Discover::MAX_BYTES)
  parsed = Feeds::Parse.call(page.text)

  if parsed.nil?
    Outcome.new(entry, :not_a_feed, entry.url)
  elsif parsed.entries.empty?
    # Parses, carries nothing. A row that puts an empty river on somebody's
    # brand-new hobby card is broken in the way that matters, even though
    # every byte of it is valid.
    Outcome.new(entry, :empty, entry.url)
  elsif page.final_url != entry.url
    Outcome.new(entry, :moved, "#{entry.url} -> #{page.final_url}")
  else
    Outcome.new(entry, :ok, "#{parsed.entries.size} items")
  end
rescue StandardError => e
  Outcome.new(entry, classify(e.message), "#{entry.url} (#{e.message})")
end

# The distinction the second full run forced, and the one that decides
# whether this job can ever be green.
#
# A 403 to an automated fetch is the publisher declining to serve robots
# from a datacenter — Cloudflare and Wordfence do it by policy, and the same
# URL answers a home connection fine. It is not evidence that the row is
# wrong, and failing on it would mean the shelf could only ever hold feeds
# whose publishers tolerate GitHub's IP ranges, which is a worse list than
# the one we want. Same for a 5xx and a timeout: the address may be perfect
# and the far end simply isn't talking to us today.
#
# What *is* evidence the row is wrong: a 404, a host that doesn't resolve, a
# certificate that doesn't verify, a body that isn't a feed, a feed with
# nothing in it. Those fail the build, because those a human has to fix.
#
# REFUSED still prints, and a REFUSED *rate* above the ceiling below fails —
# so this can't quietly become "the check passes because nothing answers".
REFUSED_CEILING = 0.20

def classify(message)
  case message
  when /HTTP (401|402|403|405|406|429)/, /HTTP 5\d\d/ then :refused
  when /Timeout/ then :refused
  else :broken
  end
end

# One queue per host so the pool can't put two fetches on the same publisher
# at once; hosts are handed out, not individual feeds.
by_host = entries.group_by { |entry| URI.parse(entry.url).host }
queue = Queue.new
by_host.each_value { |group| queue << group }
jobs.times { queue << nil }

results = Queue.new
workers = Array.new(jobs) do
  Thread.new do
    while (group = queue.pop)
      group.each do |entry|
        outcome = check(entry)
        if [ :broken, :refused, :not_a_feed ].include?(outcome.status)
          sleep RETRY_PAUSE
          outcome = check(entry)
        end
        results << outcome
      end
    end
  end
end
workers.each(&:join)
results.close

outcomes = []
while (outcome = results.pop)
  outcomes << outcome
end
# Broken first, then moved, then the quiet ones: a run with seventy things
# to fix should not open with two hundred lines of OK.
ORDER = { broken: 0, not_a_feed: 0, empty: 0, refused: 1, moved: 2, ok: 3 }.freeze
outcomes.sort_by! do |outcome|
  [ ORDER.fetch(outcome.status), outcome.entry.folder.to_s, outcome.entry.title.to_s ]
end

labels = { ok: "OK", moved: "MOVED", not_a_feed: "NOT A FEED", empty: "NO ITEMS",
            broken: "BROKEN", refused: "REFUSED" }
outcomes.each do |outcome|
  puts format("%-28s %-11s %s", outcome.entry.title.truncate(28), labels[outcome.status], outcome.detail)
end

counts = outcomes.group_by(&:status).transform_values(&:size)
counts.default = 0
broken = counts[:broken] + counts[:not_a_feed] + counts[:empty]
refused_rate = counts[:refused].fdiv(outcomes.size)

puts "\n#{outcomes.size} checked · #{counts[:ok]} OK · #{counts[:moved]} moved · " \
     "#{counts[:refused]} refused (#{(refused_rate * 100).round}%) · #{broken} broken"

if broken.positive?
  abort "\nBroken rows have no business on the shelf — fix the URL or drop the row."
elsif refused_rate > REFUSED_CEILING
  abort "\n#{(refused_rate * 100).round}% refused, over the #{(REFUSED_CEILING * 100).round}% ceiling — " \
        "that is a fetcher problem, not #{counts[:refused]} publishers having a bad day."
elsif counts[:moved].positive? && strict
  abort "\nA moved feed should be written down at the address it settled on (--strict)."
else
  puts "Moved rows still work; the file should be updated to where they landed." if counts[:moved].positive?
  puts "Refused rows are publishers turning away datacenter traffic — the URL is fine." if counts[:refused].positive?
  puts "All good."
end
