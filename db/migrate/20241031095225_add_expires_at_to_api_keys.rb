# frozen_string_literal: true

class AddExpiresAtToApiKeys < ActiveRecord::Migration[7.1]
  def change
    add_column :api_keys, :expires_at, :datetime
  end
end
