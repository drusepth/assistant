ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "webmock/minitest"
require_relative "test_helpers/session_test_helper"
require_relative "test_helpers/fake_imap_client"

# The vault's real KDF/keygen params exist to be slow; the suite shouldn't
# be. Every keyring records its own params, so this weakens nothing outside
# the test database (D-vault-crypto).
Vault::Crypto.kdf_iterations = 1_000
Vault::Crypto.rsa_bits = 2048

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
  end
end
