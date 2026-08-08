require "test_helper"

class LinkedAccountsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  test "linking a service starts with full access" do
    sign_in_as users(:one)

    assert_difference("LinkedAccount.count") do
      post linked_accounts_path, params: {
        provider: "facebook", credentials: { access_token: "fb-token" }
      }
    end
    assert_redirected_to settings_path

    account = users(:one).linked_accounts.find_by(provider: "facebook")
    assert_equal "fb-token", account.credentials["access_token"]
    assert account.full_access?
  end

  test "only declared credential fields are stored" do
    sign_in_as users(:one)

    post linked_accounts_path, params: {
      provider: "linkedin", credentials: { access_token: "li-token", admin: "true" }
    }

    account = users(:one).linked_accounts.find_by(provider: "linkedin")
    assert_equal({ "access_token" => "li-token" }, account.credentials)
  end

  test "linking with missing credentials fails politely" do
    sign_in_as users(:one)

    assert_no_difference("LinkedAccount.count") do
      post linked_accounts_path, params: { provider: "linkedin", credentials: {} }
    end
    assert_redirected_to settings_path
    assert_equal "Access token can't be blank", flash[:alert]
  end

  test "an unknown provider is rejected" do
    sign_in_as users(:one)

    assert_no_difference("LinkedAccount.count") do
      post linked_accounts_path, params: { provider: "myspace", credentials: { token: "x" } }
    end
    assert_equal "Unknown service.", flash[:alert]
  end

  test "unchecking scopes narrows what the assistant may use" do
    sign_in_as users(:one)
    account = linked_accounts(:alice_email)

    patch linked_account_path(account), params: { enabled_scopes: %w[ read_inbox ] }
    assert_redirected_to settings_path

    account.reload
    assert account.allows?("read_inbox")
    assert_not account.allows?("read_archive")
    assert_not account.allows?("send")
  end

  test "rechecking every scope restores full access" do
    sign_in_as users(:one)
    account = linked_accounts(:alice_email)
    account.update!(disabled_scopes: %w[ send ])

    patch linked_account_path(account), params: { enabled_scopes: %w[ read_inbox read_archive send ] }

    assert account.reload.full_access?
  end

  test "submitting with nothing checked disables everything" do
    sign_in_as users(:one)
    account = linked_accounts(:alice_email)

    patch linked_account_path(account)

    assert_empty account.reload.enabled_scopes
  end

  test "disconnecting deletes the link and its credentials" do
    sign_in_as users(:one)

    assert_difference("LinkedAccount.count", -1) do
      delete linked_account_path(linked_accounts(:alice_email))
    end
    assert_redirected_to settings_path
  end

  test "users cannot touch another user's links" do
    sign_in_as users(:two)
    account = linked_accounts(:alice_email)

    patch linked_account_path(account), params: { enabled_scopes: [] }
    assert_response :not_found
    assert account.reload.full_access?

    assert_no_difference("LinkedAccount.count") do
      delete linked_account_path(account)
    end
  end

  test "linking a syncable service starts a sync right away" do
    sign_in_as users(:two)

    assert_enqueued_with(job: SyncLinkedAccountJob) do
      post linked_accounts_path, params: {
        provider: "contacts",
        credentials: { server_url: "https://dav.example.com/", username: "bob@example.com", password: "pw" }
      }
    end
  end

  test "sync now enqueues a sync for a syncable link" do
    sign_in_as users(:one)
    account = linked_accounts(:alice_contacts)

    assert_enqueued_with(job: SyncLinkedAccountJob, args: [ account ]) do
      post sync_linked_account_path(account)
    end
    assert_redirected_to settings_path
  end

  test "providers without a sync consumer cannot be synced" do
    sign_in_as users(:one)

    assert_no_enqueued_jobs do
      post sync_linked_account_path(linked_accounts(:alice_email))
    end
    assert_equal "Email — Personal doesn't sync yet.", flash[:alert]
  end

  test "users cannot sync another user's link" do
    sign_in_as users(:two)

    assert_no_enqueued_jobs do
      post sync_linked_account_path(linked_accounts(:alice_contacts))
    end
    assert_response :not_found
  end

  test "settings shows connected accounts with their scope dials" do
    sign_in_as users(:one)

    get settings_path
    assert_response :success
    assert_select "h2", text: "Connected accounts"
    assert_select "input[name='enabled_scopes[]'][value=read_inbox][checked]"
    assert_select "form[action=?]", linked_accounts_path
  end
end
