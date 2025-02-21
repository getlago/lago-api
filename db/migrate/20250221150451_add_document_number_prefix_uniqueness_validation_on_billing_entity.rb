# frozen_string_literal: true

class AddDocumentNumberPrefixUniquenessValidationOnBillingEntity < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!
  def change
    safety_assured do
      add_index :billing_entities, %i[organization_id document_number_prefix], unique: true, algorithm: :concurrently
    end
  end
end
