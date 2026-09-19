require "test_helper"

# Your own Eventbrite tickets (D-radar-accounts): every order's event is a
# commitment and goes onto the calendar, deduped like an upload.
class Eventbrite::OrdersSyncTest < ActiveJob::TestCase
  PUBLIC_DNS = Class.new { def getaddresses(_host) = [ "93.184.216.34" ] }.new

  setup do
    Web::Fetch.resolver = PUBLIC_DNS
    @user = users(:one)
    @account = @user.linked_accounts.create!(provider: "eventbrite", credentials: { "token" => "private-token" })
  end

  teardown { Web::Fetch.resolver = Resolv }

  def orders(events, more: false)
    { orders: events.map { |event| { id: "o#{event[:id]}", event: event } },
      pagination: { has_more_items: more, continuation: more ? "next" : nil } }.to_json
  end

  def event(id:, name:, at:, status: "live")
    { id: id, name: { text: name }, description: { text: "Bring ID." }, url: "https://www.eventbrite.com/e/#{id}",
      status: status, start: { utc: at.utc.iso8601, timezone: "America/Chicago" }, end: { utc: (at + 2.hours).utc.iso8601 },
      venue: { name: "Cain's Ballroom", address: { localized_address_display: "423 N Main St, Tulsa, OK" } } }
  end

  test "tickets land on the calendar with venue and link, cancelled ones don't, and pages are followed" do
    show = 6.days.from_now.change(hour: 20)
    stub_request(:get, %r{eventbriteapi\.com/v3/users/me/orders/\?.*expand=event}).with(headers: { "Authorization" => "Bearer private-token" })
      .to_return({ body: orders([ event(id: 1, name: "Jazz night", at: show) ], more: true), headers: { "Content-Type" => "application/json" } },
                 { body: orders([ event(id: 2, name: "Cancelled show", at: show, status: "canceled") ]), headers: { "Content-Type" => "application/json" } })

    result = Eventbrite::OrdersSync.new(@account).call

    assert_equal 1, result.imported
    jazz = @user.events.find_by!(title: "Jazz night")
    assert_equal "Cain's Ballroom, 423 N Main St, Tulsa, OK", jazz.location
    assert_match "Link: https://www.eventbrite.com/e/1", jazz.description
    assert_equal [ "hobbies" ], jazz.sections.map(&:slug)
    assert_nil @user.events.find_by(title: "Cancelled show")
    assert_requested :get, %r{eventbriteapi\.com}, times: 2
  end

  test "fails closed with the read scope off, and a bad token lands on the link" do
    @account.update!(disabled_scopes: [ "read" ])
    assert_raises(Eventbrite::OrdersSync::Error) { Eventbrite::OrdersSync.new(@account).call }

    @account.update!(disabled_scopes: [])
    stub_request(:get, %r{eventbriteapi\.com}).to_return(status: 401)
    SyncLinkedAccountJob.perform_now(@account)

    assert_match(/401/, @account.reload.sync_error)
  end
end
