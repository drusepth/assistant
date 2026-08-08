class CreateJobFeeds < ActiveRecord::Migration[8.1]
  def change
    # The job scout's sources (D-career-web): per-user feed/board URLs — RSS/Atom,
    # Greenhouse and Lever public boards, USAJobs — scanned on the agent
    # cadence. ToS-clean by construction: feeds and open APIs only.
    create_table :job_feeds do |t|
      t.references :user, null: false, foreign_key: true
      t.string :url, null: false
      t.string :label
      t.string :kind, null: false, default: "rss"
      t.string :api_key
      t.datetime :last_scanned_at
      t.string :last_error
      t.timestamps
    end
  end
end
