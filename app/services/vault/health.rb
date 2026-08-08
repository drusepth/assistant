module Vault
  # The stewardship report (PASSWORDS_PLAN W4): weak / common / reused /
  # aging, computed in-request over the unlocked owner's own entries and
  # never stored anywhere. The common-password list rides the
  # D-public-datasets layer — a seeded file the admin can replace with a
  # bigger import; absent file degrades to the entropy checks alone.
  class Health
    DATASET = "common_passwords.txt".freeze
    WEAK_BITS = 40
    AGING_AFTER = 1.year

    Finding = Struct.new(:credential, :problems)
    Report = Struct.new(:findings, :checked, :dataset_size)

    def initialize(user, vault_key)
      @user = user
      @vault_key = vault_key
    end

    def call
      common = common_passwords
      passwords = {}

      @user.credentials.where.not(kind: "note").find_each do |credential|
        secrets = credential.read_secrets(@user, @vault_key)
        passwords[credential] = secrets && secrets["password"]
      end

      counts = passwords.values.compact.tally

      findings = passwords.filter_map do |credential, password|
        next if password.blank?

        problems = []
        problems << "common" if common.include?(password.downcase)
        problems << "weak" if entropy_bits(password) < WEAK_BITS
        problems << "reused" if counts[password] > 1
        problems << "aging" if credential.secret_changed_at && credential.secret_changed_at < AGING_AFTER.ago
        next if problems.empty?

        Finding.new(credential, problems)
      end

      Report.new(findings.sort_by { |f| -f.problems.size }, passwords.size, common.size)
    end

    # Charset-size estimate — honest enough to rank, no zxcvbn dependency.
    def entropy_bits(password)
      pool = 0
      pool += 26 if password =~ /[a-z]/
      pool += 26 if password =~ /[A-Z]/
      pool += 10 if password =~ /\d/
      pool += 33 if password =~ /[^a-zA-Z\d]/
      return 0 if pool.zero?

      (password.length * Math.log2(pool)).round
    end

    private
      def common_passwords
        path = Datasets.read_path(DATASET)
        return Set.new if path.nil?

        @common ||= path.read.split("\n").map { |line| line.strip.downcase }.reject(&:empty?).to_set
      end
  end
end
