# frozen_string_literal: true

class RemoveCreditsAutoRefreshedFromOrganizations < ActiveRecord::Migration[7.0]
  def change
    remove_column :organizations, :credits_auto_refreshed, :boolean
  end
end
