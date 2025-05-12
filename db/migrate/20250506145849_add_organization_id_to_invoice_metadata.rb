# frozen_string_literal: true

class AddOrganizationIdToInvoiceMetadata < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  def change
    add_reference :invoice_metadata, :organization, type: :uuid, index: {algorithm: :concurrently}
  end
end
