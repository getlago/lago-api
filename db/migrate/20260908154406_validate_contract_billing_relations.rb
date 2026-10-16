# frozen_string_literal: true

class ValidateContractBillingRelations < ActiveRecord::Migration[8.0]
  def change
    validate_foreign_key :contracts, :billing_entities, column: :billing_entity_id
    validate_foreign_key :contracts, :payment_methods, column: :payment_method_id
  end
end
