# frozen_string_literal: true

class AddEmailSettingsToOrganizations < ActiveRecord::Migration[7.0]
  def change
    add_column :organizations, :email_settings, :string, array: true, default: [], null: false
  end
end
