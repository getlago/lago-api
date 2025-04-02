# frozen_string_literal: true

class AssignFeeToOrganization < ActiveRecord::Migration[7.2]
  def up
    Migrate::PopulateFeesWithOrganizationIdJob.perform_later
  end

  def down
    # no-op
  end
end
