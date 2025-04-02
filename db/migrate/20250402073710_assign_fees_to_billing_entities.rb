# frozen_string_literal: true

class AssignFeesToBillingEntities < ActiveRecord::Migration[7.2]
  def up
    Migrate::PopulateFeesWithBillingEntityJob.perform_later
  end

  def down
  end
end
