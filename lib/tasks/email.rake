# The triage scorecard (EMAIL_PLAN.md §6): runs the labeled corpus
# against the household's configured model and prints per-case results.
# Quality is measured, not vibed — run this before shipping prompt
# changes, or to answer "is this local model good enough for mail?".
namespace :email do
  desc "Score the email triage prompt against the labeled corpus"
  task triage_eval: :environment do
    user = User.order(:id).first or abort "No users yet — set the instance up first."
    profile = user.household.model_profile
    abort "No model configured — add one in Settings." unless profile&.configured?

    corpus = YAML.safe_load(
      ERB.new(File.read(Rails.root.join("test/fixtures/files/email_triage_corpus.yml"))).result,
      permitted_classes: [ Date ], aliases: true)
    sample = Struct.new(:direction, :from_name, :from_email, :to_emails, :sent_at, :subject, :body_text, keyword_init: true)
    triage = Email::Triage.new(user: user, profile: profile)

    passes = 0
    corpus.each do |entry|
      message = sample.new(
        direction: entry.fetch("direction", "inbound"),
        from_name: entry["from_name"], from_email: entry["from"],
        to_emails: [ entry.fetch("to", "you@example.com") ],
        sent_at: Time.current, subject: entry["subject"], body_text: entry["body"])

      label = triage.classify([ message ])[1]
      failures = score(entry.fetch("expect"), label)

      if failures.empty?
        passes += 1
        puts "PASS  #{entry['name']}  → #{label && "#{label['category']}/#{label['importance']}"}"
      else
        puts "FAIL  #{entry['name']}  → #{label ? "#{label['category']}/#{label['importance']}" : "no valid label"}: #{failures.join('; ')}"
      end
    rescue Llm::Error => e
      puts "ERROR #{entry['name']}: #{e.message}"
    end

    puts "\n#{passes}/#{corpus.size} passed against #{profile.display_name}"
  end

  def score(expect, label)
    return [ "model returned no valid label" ] if label.nil?
    failures = []

    if expect["category"]
      allowed = Array(expect["category"]).map(&:to_s)
      failures << "category #{label['category']} not in #{allowed.join('|')}" unless allowed.include?(label["category"])
    end
    if expect["importance_min"] && label["importance"] < expect["importance_min"]
      failures << "importance #{label['importance']} < #{expect['importance_min']}"
    end
    if expect["importance_max"] && label["importance"] > expect["importance_max"]
      failures << "importance #{label['importance']} > #{expect['importance_max']}"
    end
    if expect.key?("expects_reply") && label["expects_reply"] != expect["expects_reply"]
      failures << "expects_reply #{label['expects_reply']}"
    end
    if (days = expect["deadline_days_from_now"])
      target = Date.current + days
      actual = label["deadline_on"] && Date.iso8601(label["deadline_on"])
      failures << "deadline #{actual || 'missing'} != ~#{target}" unless actual && (actual - target).abs <= 2
    end

    failures
  end
end
