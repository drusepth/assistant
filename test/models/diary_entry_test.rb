require "test_helper"

# The diary's crypto tier (D-diary-vault): the owner reads through the diary
# key, capture works while locked, reading repairs a locked write, and a
# password reset without the recovery code seals the whole journal for good.
class DiaryEntryTest < ActiveSupport::TestCase
  setup do
    @owner = users(:one)
    @keyring = Keyring.initialize_for(@owner, "password")
    @vault_key = @keyring.unlock("password")
    @session = Diary::Session.new(@owner, @vault_key)
  end

  def write(title: "A day", body: "It rained all afternoon.", on: Date.current, session: @session)
    entry = @owner.diary_entries.new(entry_date: on)
    session.write!(entry, { "title" => title, "body" => body })
    entry
  end

  test "round-trips through the owner's diary key" do
    entry = write(body: "It rained all afternoon.")

    payload = Diary::Session.new(@owner, @vault_key).read(entry.reload)
    assert_equal "A day", payload["title"]
    assert_equal "It rained all afternoon.", payload["body"]
    assert_not_nil entry.edited_at
  end

  test "the owner's wrap is under the diary key, not an RSA key row" do
    entry = write

    assert_equal DiaryEntry::SCHEME_DIARY_KEY, entry.owner_wrapped_item_key.b.byteslice(0)
    assert_empty entry.diary_entry_keys, "the owner must never hold a key row"
    assert_not entry.wrapped_while_locked?
  end

  test "nothing but the date survives in the clear" do
    entry = write(title: "Unmistakable Title", body: "Unmistakable body text.")

    row = DiaryEntry.connection.select_one("SELECT * FROM diary_entries WHERE id = #{entry.id}")
    assert_no_match(/Unmistakable/, row.values.map(&:to_s).join(" "))
    assert_equal Date.current.to_s, row["entry_date"].to_s
  end

  test "capture works while locked and the next unlocked read repairs the wrap" do
    locked = Diary::Session.new(@owner, nil)
    entry = write(body: "Written with the vault locked.", session: locked)

    assert entry.wrapped_while_locked?
    assert_equal DiaryEntry::SCHEME_RSA, entry.owner_wrapped_item_key.b.byteslice(0)
    assert_nil locked.read(entry), "a locked session must not be able to read it back"

    unlocked = Diary::Session.new(@owner, @vault_key)
    assert_equal "Written with the vault locked.", unlocked.read(entry.reload)["body"]

    assert_not entry.reload.wrapped_while_locked?, "the read should have re-wrapped it"
    assert_equal "Written with the vault locked.", Diary::Session.new(@owner, @vault_key).read(entry)["body"]
  end

  test "editing keeps the item key so grantee wraps survive" do
    entry = write(body: "First draft.")
    before = entry.owner_wrapped_item_key

    assert Diary::Session.new(@owner, @vault_key).update!(entry, { "body" => "Second draft." })

    assert_equal before, entry.reload.owner_wrapped_item_key
    assert_equal "Second draft.", Diary::Session.new(@owner, @vault_key).read(entry)["body"]
    assert_equal "A day", Diary::Session.new(@owner, @vault_key).read(entry)["title"], "unsent fields are kept"
  end

  test "another household member cannot read it, vault of their own or not" do
    entry = write
    other = users(:two)
    other_key = Keyring.initialize_for(other, "password").unlock("password")

    assert_nil DiaryEntry.new.unwrap_item_key(other, other_key)
    assert_nil Diary::Session.new(other, other_key).read(entry)
    assert_not entry.visible_to?(other)
  end

  test "a section-wide grant can never reach a diary entry" do
    entry = write
    other = users(:two)
    section = Section.find_by(slug: "health") || Section.create!(name: "Health", slug: "health", position: 98)
    AccessGrant.create!(grantor: @owner, grantee: other, subject: section)

    assert_not entry.visible_to?(other), "the diary carries no taggings, so no section clause can match"
  end

  test "payload is bound to its AAD" do
    entry = write
    item_key = entry.unwrap_item_key(@owner, @vault_key)

    moved = @owner.credentials.create!(name: "Bank", kind: "login")
    moved.update_column(:secrets_ciphertext, entry.payload_ciphertext)

    assert_nil moved.reload.read_secrets_with_item_key(item_key)
  end

  test "a password reset without the recovery code seals the whole journal" do
    entry = write(body: "Before the reset.")
    assert_not entry.lost_for?(@owner, @vault_key)

    @keyring.reset!("a-new-password")
    new_vault_key = @keyring.reload.unlock("a-new-password")

    assert entry.reload.lost_for?(@owner, new_vault_key)
    assert_nil Diary::Session.new(@owner, new_vault_key).read(entry)
    assert_equal Date.current, entry.entry_date, "dates survive; only the writing is gone"
  end

  test "after a reset the diary re-keys itself so writing works again" do
    write(body: "Before the reset.")
    @keyring.reset!("a-new-password")
    new_vault_key = @keyring.reload.unlock("a-new-password")

    session = Diary::Session.new(@owner, new_vault_key)
    fresh = write(body: "After the reset.", session: session)

    assert_equal "After the reset.", Diary::Session.new(@owner, new_vault_key).read(fresh.reload)["body"]
    assert session.lost_entries?, "the diary should say when its key was broken"
  end

  test "the recovery code carries the diary through a reset" do
    entry = write(body: "Kept.")
    code = @keyring.generate_recovery!(@vault_key)

    recovered = @keyring.unlock_with_recovery(code)
    @keyring.rewrap!(recovered, "a-new-password")

    assert_equal "Kept.", Diary::Session.new(@owner, @keyring.reload.unlock("a-new-password")).read(entry)["body"]
  end
end
