# frozen_string_literal: true

class RenameIntegrationItemsColumns < ActiveRecord::Migration[7.0]
  def change
    safety_assured do
      rename_column :integration_items, :name, :external_name
      rename_column :integration_items, :account_code, :external_account_code
    end
  end
end
