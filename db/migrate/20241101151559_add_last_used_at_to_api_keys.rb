# frozen_string_literal: true

class AddLastUsedAtToApiKeys < ActiveRecord::Migration[7.1]
  def change
    add_column :api_keys, :last_used_at, :datetime
  end
end
