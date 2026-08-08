require "test_helper"

# Emergency access (PASSWORDS_PLAN §7): escrow at setup, request starts the
# clock, deny clears it, and an undenied wait releases read-only access
# through the contact's own unlocked vault.
class EmergencyContactsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @owner = users(:one)
    @contact = users(:two)

    post session_url, params: { email_address: @contact.email_address, password: "password" }
    delete session_url

    post session_url, params: { email_address: @owner.email_address, password: "password" }
    post credentials_url, params: { credential: { kind: "login", name: "Bank", username: "drew" },
                                    secrets: { password: "escrowed-1" } }
    @credential = Credential.last

    post emergency_contacts_url, params: { contact_user_id: @contact.id, wait_days: 3 }
    @escrow = EmergencyContact.last
    delete session_url
  end

  test "setup escrows the vault key to the contact" do
    assert_equal @contact, @escrow.contact_user
    assert_equal 3, @escrow.wait_days
    assert_not @escrow.requested?
  end

  test "access is refused before the wait elapses and opens after it" do
    post session_url, params: { email_address: @contact.email_address, password: "password" }

    get access_emergency_contact_url(@escrow)
    assert_redirected_to credentials_url # not even requested yet

    post request_access_emergency_contact_url(@escrow)
    get access_emergency_contact_url(@escrow)
    assert_redirected_to credentials_url # clock running, not elapsed

    travel 4.days do
      # The 12h unlock window expired during the wait — re-unlock first.
      post unlock_credentials_url, params: { password: "password" }
      get access_emergency_contact_url(@escrow)
      assert_response :success
      assert_match "Bank", response.body
      assert_no_match "escrowed-1", response.body # read via reveal only

      post emergency_reveal_emergency_contact_url(@escrow),
        params: { credential_id: @credential.id, field: "password" }
      assert_equal "escrowed-1", response.parsed_body["value"]
      assert_not_nil @escrow.reload.released_at
    end
  end

  test "deny clears the request and the wait never elapses" do
    post session_url, params: { email_address: @contact.email_address, password: "password" }
    post request_access_emergency_contact_url(@escrow)
    delete session_url

    post session_url, params: { email_address: @owner.email_address, password: "password" }
    post deny_emergency_contact_url(@escrow)
    assert_not @escrow.reload.requested?
    delete session_url

    post session_url, params: { email_address: @contact.email_address, password: "password" }
    travel 10.days do
      get access_emergency_contact_url(@escrow)
      assert_redirected_to credentials_url
    end
  end

  test "every step of an emergency request lands in the owner's log" do
    post session_url, params: { email_address: @contact.email_address, password: "password" }
    post request_access_emergency_contact_url(@escrow)
    travel 4.days do
      post unlock_credentials_url, params: { password: "password" }
      get access_emergency_contact_url(@escrow)
    end

    actions = @owner.vault_events.newest_first.map(&:action)
    assert_equal %w[ emergency_opened emergency_requested emergency_added ], actions
    assert_match "opened emergency access to your vault", @owner.vault_events.newest_first.first.describe
  end

  test "revoke removes the escrow" do
    post session_url, params: { email_address: @owner.email_address, password: "password" }
    assert_difference "EmergencyContact.count", -1 do
      delete emergency_contact_url(@escrow)
    end
  end

  test "only the named contact can request or read" do
    outsider = users(:outsider)
    post session_url, params: { email_address: outsider.email_address, password: "password" }

    post request_access_emergency_contact_url(@escrow)
    assert_response :not_found
    get access_emergency_contact_url(@escrow)
    assert_response :not_found
  end
end
