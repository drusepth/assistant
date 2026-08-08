module Admin
  # The /admin storage panel (extends D23): which Active Storage service
  # this instance runs on, and how much of it each member is using —
  # counts and byte totals only, never contents (D9).
  class StorageStatus
    ATTACHED = { "Photo" => :photos, "Document" => :documents }.freeze

    def initialize(household)
      @household = household
    end

    def service
      Rails.application.config.active_storage.service
    end

    def per_member
      @household.users.order(:name).map do |member|
        {
          user: member,
          photos: member.photos.count,
          documents: member.documents.count,
          bytes: bytes_for(member)
        }
      end
    end

    def total_bytes
      @total_bytes ||= per_member.sum { |row| row[:bytes] }
    end

    private
      def bytes_for(member)
        ATTACHED.sum do |record_type, association|
          ActiveStorage::Blob.joins(:attachments).where(active_storage_attachments: {
            record_type: record_type, record_id: member.public_send(association).select(:id)
          }).sum(:byte_size)
        end
      end
  end
end
