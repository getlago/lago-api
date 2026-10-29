# frozen_string_literal: true

class AddBusyAtToAiConversations < ActiveRecord::Migration[8.1]
  def change
    add_column :ai_conversations, :busy_at, :datetime, if_not_exists: true
  end
end
