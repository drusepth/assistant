# Bundled public data (D31): public-domain statistics served from local
# files so Tier-A tools can cite real numbers without scraping or per-user
# web calls. Two-layer lookup — `storage/datasets/` (refreshed or imported)
# wins over the `db/datasets/` seeds — and every consumer shows the data's
# as-of year: staleness is displayed, never silent.
module Datasets
  SEED_DIR = Rails.root.join("db/datasets")

  # Overridable so tests write to a tmpdir instead of the instance's storage.
  mattr_accessor :store_dir, default: Rails.root.join("storage/datasets")

  module_function

  def read_path(filename)
    stored = Pathname(store_dir).join(filename)
    return stored if stored.exist?

    seeded = SEED_DIR.join(filename)
    seeded if seeded.exist?
  end

  def write!(filename, content)
    Pathname(store_dir).tap(&:mkpath).join(filename).write(content)
  end
end
