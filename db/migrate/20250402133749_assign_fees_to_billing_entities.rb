# frozen_string_literal: true

class AssignFeesToBillingEntities < ActiveRecord::Migration[7.2]
  def up
    # this migration runs after the populate_fees_with_organization_id_job, so
    # we want it to be scheduled after all batch jobs of that job
    Migrate::PopulateFeesWithBillingEntityJob.set(wait: 30.minutes).perform_later
  end

  def down
  end
end
