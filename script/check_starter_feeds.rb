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
  page = Web::Fetch.raw(entry.url, headers: { "Accept" => Feeds::Discover::ACCEPT })
  parsed = Feeds::Parse.call(page.text)

  if parsed.nil?
    Outcome.new(entry, :not_a_feed, entry.url)
  elsif page.final_url != entry.url
    Outcome.new(entry, :moved, "#{entry.url} -> #{page.final_url}")
  else
    Outcome.new(entry, :ok, "#{parsed.entries.size} items")
  end
rescue StandardError => e
  Outcome.new(entry, :failed, "#{entry.url} (#{e.message})")
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
        if outcome.status != :ok && outcome.status != :moved
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
outcomes.sort_by! { |outcome| [ outcome.entry.folder.to_s, outcome.entry.title.to_s ] }

labels = { ok: "OK", moved: "MOVED", not_a_feed: "NOT A FEED", failed: "FAILED" }
outcomes.each do |outcome|
  puts format("%-28s %-11s %s", outcome.entry.title.truncate(28), labels[outcome.status], outcome.detail)
end

moved = outcomes.count { |outcome| outcome.status == :moved }
broken = outcomes.count { |outcome| [ :not_a_feed, :failed ].include?(outcome.status) }

puts "\n#{outcomes.size} checked · #{outcomes.size - moved - broken} OK · #{moved} moved · #{broken} broken"
if broken.positive?
  abort "\nBroken rows have no business on the shelf — fix the URL or drop the row."
elsif moved.positive? && strict
  abort "\nA moved feed should be written down at the address it settled on (--strict)."
elsif moved.positive?
  puts "Moved rows still work, but the file should be updated to where they landed."
else
  puts "All good."
end
