# frozen_string_literal: true

class AssignFeesToBillingEntities < ActiveRecord::Migration[7.2]
  def up
    Fee.where(billing_entity_id: nil).find_in_batches(batch_size: 5000) do |batch|
      Fee.where(id: batch.pluck(:id))
        .update_all("billing_entity_id = organization_id") # rubocop:disable Rails/SkipsModelValidations
    end
  end

  def down
  end
end
