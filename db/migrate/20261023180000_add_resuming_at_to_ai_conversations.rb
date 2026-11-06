# frozen_string_literal: true

class AddResumingAtToAiConversations < ActiveRecord::Migration[8.1]
  def change
    add_column :ai_conversations, :resuming_at, :datetime, if_not_exists: true
  end
end
