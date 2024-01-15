# frozen_string_literal: true

class AddCreditsAutoRefreshedToOrganizations < ActiveRecord::Migration[7.0]
  def change
    add_column :organizations, :credits_auto_refreshed, :boolean, default: false, null: false
  end
end
