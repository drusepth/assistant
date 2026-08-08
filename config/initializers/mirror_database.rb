# The email FTS index is an FTS5 virtual table maintained from model
# callbacks and created lazily (Email::Search) — schema dumps can't
# represent virtual tables, so keep it out of them.
ActiveRecord::SchemaDumper.ignore_tables |= [ "email_messages_fts", /email_messages_fts_.*/ ]
