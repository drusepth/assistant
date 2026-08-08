# A source the job scout watches for one user (D32): a feed or open board
# API — never a scraped site. Kind is sniffed from the URL at save so the
# user just pastes a link; USAJobs additionally wants their free API key.
class JobFeed < ApplicationRecord
  belongs_to :user

  KINDS = %w[ rss greenhouse lever usajobs ].freeze

  validates :url, presence: true, format: { with: %r{\Ahttps?://}i, message: "must be an http(s) link" }
  validates :kind, inclusion: { in: KINDS }

  before_validation :detect_kind, if: -> { url_changed? }

  scope :due_for_scan, -> { where(last_scanned_at: [ nil, ..20.hours.ago ]) }

  def display_label
    label.presence || host || url
  end

  # The URL the scout actually fetches: board pages normalize to their
  # public JSON APIs so we read data, not markup.
  def fetch_url
    case kind
    when "greenhouse"
      return url if host&.start_with?("boards-api.")

      org = path_org
      org ? "https://boards-api.greenhouse.io/v1/boards/#{org}/jobs" : url
    when "lever"
      return url if host&.start_with?("api.")

      org = path_org
      org ? "https://api.lever.co/v0/postings/#{org}?mode=json" : url
    else
      url
    end
  end

  # USAJobs authenticates with a free key plus the holder's email as the
  # user agent — their documented convention.
  def fetch_headers
    return {} unless kind == "usajobs"

    { "Authorization-Key" => api_key.to_s, "User-Agent" => user.email_address.to_s }
  end

  def company_hint
    case kind
    when "greenhouse", "lever" then path_org&.tr("-", " ")&.titleize
    when "usajobs" then nil
    else label.presence || host
    end
  end

  private
    def host
      URI.parse(url.to_s).host
    rescue URI::InvalidURIError
      nil
    end

    def path_org
      URI.parse(url.to_s).path.split("/").reject(&:blank?).first
    rescue URI::InvalidURIError
      nil
    end

    def detect_kind
      host = URI.parse(url.to_s).host.to_s.downcase
      self.kind =
        if host.end_with?("greenhouse.io") then "greenhouse"
        elsif host.end_with?("lever.co") then "lever"
        elsif host.end_with?("usajobs.gov") then "usajobs"
        else "rss"
        end
    rescue URI::InvalidURIError
      self.kind = "rss"
    end
end
