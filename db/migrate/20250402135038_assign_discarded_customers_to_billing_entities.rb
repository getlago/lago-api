# frozen_string_literal: true

class AssignDiscardedCustomersToBillingEntities < ActiveRecord::Migration[7.2]
  def up
    Customer.with_discarded.where("billing_entity_id != organization_id").or(Customer.with_discarded.where(billing_entity_id: nil)).find_in_batches(batch_size: 1000) do |batch|
      Customer.with_discarded.where(id: batch.pluck(:id))
        .update_all("billing_entity_id = organization_id")
    end
  end

  def down
  end
end
