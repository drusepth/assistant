#!/usr/bin/env ruby
# Verifies config/starter_feeds.opml against the live web (D-hobby-feeds §7.1).
#
# The starter list ships in the repo, so it rots silently: a publisher moves
# a feed, drops RSS, or puts it behind a redirect to somebody else's
# aggregator, and the shelf keeps offering it. Run this before changing the
# file, and periodically:
#
#   bin/rails runner script/check_starter_feeds.rb
#
# Reports one line per feed: OK, MOVED (with the address it settled on — put
# that in the file), or the failure. A feed that can't be fetched or parsed
# has no business being offered to somebody who has never used a reader.
require "net/http"

entries = Feeds::Starters.reload!.entries
abort "No entries in #{Feeds::Starters.path}" if entries.empty?

puts "Checking #{entries.size} starter feeds…\n\n"
failures = 0

entries.each do |entry|
  page = Web::Fetch.raw(entry.url, headers: { "Accept" => Feeds::Discover::ACCEPT })
  parsed = Feeds::Parse.call(page.text)

  if parsed.nil?
    failures += 1
    puts format("%-22s NOT A FEED  %s", entry.title, entry.url)
  elsif page.final_url != entry.url
    puts format("%-22s MOVED       %s -> %s", entry.title, entry.url, page.final_url)
  else
    puts format("%-22s OK          %d items", entry.title, parsed.entries.size)
  end
rescue StandardError => e
  failures += 1
  puts format("%-22s FAILED      %s (%s)", entry.title, entry.url, e.message)
end

puts "\n#{failures.zero? ? "All good." : "#{failures} need attention."}"
