# frozen_string_literal: true

class AddSecurityLogsRetentionDaysToOrganizations < ActiveRecord::Migration[8.0]
  def change
    add_column :organizations, :security_logs_retention_days, :integer
  end
end
