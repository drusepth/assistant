require "test_helper"

class VaultPagesControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:one) }

  test "lists every vault page as a card with its blurb" do
    get vault_pages_path
    assert_response :success

    VaultPage::ALL.each do |page|
      assert_select "#vault_page_#{page.slug}"
      assert_match ERB::Util.html_escape(page.blurb), response.body
    end
  end

  test "turning a page off hides it from the sidebar and deletes nothing" do
    note_count = Note.count

    patch vault_page_path("diary"), params: { enabled: "0" }
    assert_redirected_to vault_pages_path
    assert_not users(:one).reload.vault_page_enabled?("diary")

    follow_redirect!
    assert_select "nav a[href=?]", diary_entries_path, count: 0
    assert_select "button[aria-label=?]", "Turn on Diary"

    patch vault_page_path("notes"), params: { enabled: "0" }
    assert_equal note_count, Note.count
  end

  test "turning a page back on returns it to the sidebar" do
    users(:one).update!(hidden_vault_pages: [ "passwords" ])

    patch vault_page_path("passwords"), params: { enabled: "1" }
    assert users(:one).reload.vault_page_enabled?("passwords")

    follow_redirect!
    assert_select "nav a[href=?]", credentials_path
  end

  test "a hidden page's URL still works" do
    users(:one).update!(hidden_vault_pages: [ "recipes" ])
    get recipes_path
    assert_response :success
  end

  test "Mail stays out of the sidebar until an email account is linked, and says so" do
    users(:one).linked_accounts.where(provider: "email").destroy_all

    get vault_pages_path
    assert_select "nav a[href=?]", mail_index_path, count: 0
    assert_select "#vault_page_mail a", text: "Connect an email account"
  end

  test "an empty vault leaves a way back to the picker" do
    users(:one).update!(hidden_vault_pages: VaultPage::SLUGS)

    get root_path
    assert_select "nav a[href=?]", vault_pages_path, minimum: 2
    assert_select "nav a[href=?]", people_path, count: 0
  end

  test "unknown pages are not found" do
    patch vault_page_path("spaceship"), params: { enabled: "0" }
    assert_response :not_found
  end

  test "the sidebar links to the picker" do
    get root_path
    assert_select "nav a[href=?]", vault_pages_path
  end
end
