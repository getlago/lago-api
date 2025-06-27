# frozen_string_literal: true

class AddEnabledAuthsToOrganizations < ActiveRecord::Migration[8.0]
  def change
    add_column :organizations, :enabled_auths, :string, array: true, null: false, default: ["password", "google_oauth"]
  end
end
