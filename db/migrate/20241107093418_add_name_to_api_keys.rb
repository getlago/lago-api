# frozen_string_literal: true

class AddNameToApiKeys < ActiveRecord::Migration[7.1]
  def change
    add_column :api_keys, :name, :string
  end
end
