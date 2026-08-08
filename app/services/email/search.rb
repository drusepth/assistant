# Full-text search over the mirror (EMAIL_PLAN.md §4): an FTS5 virtual
# table beside email_messages, maintained from model callbacks rather than
# triggers (schema.rb can't dump either, so the index is created lazily
# and idempotently — a schema-loaded test database gets it on first use).
# Where the SQLite build lacks FTS5, everything degrades to LIKE.
class Email::Search
  TABLE = "email_messages_fts"

  class << self
    def available?
      ensure_index!
    end

    def index(message)
      return unless ensure_index!
      remove(message)
      connection.execute(sanitize(<<~SQL, message.id, message.subject.to_s, message.body_text.to_s))
        INSERT INTO #{TABLE}(rowid, subject, body_text) VALUES (?, ?, ?)
      SQL
    end

    def remove(message)
      return unless ensure_index!
      connection.execute(sanitize("DELETE FROM #{TABLE} WHERE rowid = ?", message.id))
    end

    def remove_ids(ids)
      return if ids.empty? || !ensure_index!
      connection.execute(sanitize("DELETE FROM #{TABLE} WHERE rowid IN (?)", ids.map(&:to_i)))
    end

    # Message ids matching the query, unscoped — callers MUST re-filter by
    # user (EmailMessage.where(id: ids, user_id: ...)). Returns nil when
    # FTS is unavailable so callers can fall back to LIKE.
    def match_ids(query, limit: 200)
      return nil unless ensure_index!
      match = fts_expression(query)
      return [] if match.blank?
      connection.select_values(sanitize(<<~SQL, match, limit))
        SELECT rowid FROM #{TABLE} WHERE #{TABLE} MATCH ? ORDER BY rank LIMIT ?
      SQL
    rescue ActiveRecord::StatementInvalid
      []
    end

    # Rebuild-safe: user text becomes quoted FTS tokens, never syntax.
    def fts_expression(query)
      query.to_s.scan(/[[:alnum:]@.'\-]+/).map { |token| %("#{token.delete('"')}") }.join(" ")
    end

    private
      def connection = MirrorRecord.connection

      # Runs the (cheap, idempotent) DDL on every call rather than
      # memoizing existence — test transactions roll the table back, and
      # a fresh schema-loaded database starts without it. Only "this
      # SQLite build has no FTS5" is remembered.
      def ensure_index!
        return false if @unsupported
        connection.execute("CREATE VIRTUAL TABLE IF NOT EXISTS #{TABLE} USING fts5(subject, body_text)")
        true
      rescue ActiveRecord::StatementInvalid
        @unsupported = true
        false
      end

      def sanitize(sql, *binds)
        ActiveRecord::Base.sanitize_sql_array([ sql, *binds ])
      end
  end
end
