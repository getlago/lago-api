# frozen_string_literal: true

class AddTimezoneToOrganizations < ActiveRecord::Migration[7.0]
  def change
    add_column :organizations, :timezone, :string, null: false, default: "UTC"
  end
end
