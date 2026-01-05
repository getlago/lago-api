# frozen_string_literal: true

class AddApiRateLimitsToOrganization < ActiveRecord::Migration[8.0]
  def change
    add_column :organizations, :api_rate_limits, :jsonb, default: {}, null: false
  end
end
