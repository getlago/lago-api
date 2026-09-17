# frozen_string_literal: true

class ValidateQuoteVersionsBillingEntityForeignKey < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    validate_foreign_key :quote_versions, :billing_entities
  end
end
