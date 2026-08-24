# The id an optimistically-rendered bubble was drawn with, so the morph that
# follows the send can match the server's turn to the one already on screen
# instead of removing one and inserting the other (CHAT_PLAN.md
# D-chat-optimistic). Nullable and unindexed on purpose: it is a per-send
# handshake, never looked up.
class AddClientTokenToToolRunMessages < ActiveRecord::Migration[8.1]
  def change
    add_column :tool_run_messages, :client_token, :string
  end
end
