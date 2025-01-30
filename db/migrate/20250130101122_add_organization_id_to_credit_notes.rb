# frozen_string_literal: true

class AddOrganizationIdToCreditNotes < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    add_reference :credit_notes, :organization, type: :uuid, index: {algorithm: :concurrently}

    add_foreign_key :credit_notes, :organizations, validate: false
    validate_foreign_key :credit_notes, :organizations
  end
end
