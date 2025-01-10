class AddRecipientAndIssuerToInvoices < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    add_reference :invoices, :recipient, polymorphic: true, type: :uuid, index: {algorithm: :concurrently}
    add_reference :invoices, :issuer, polymorphic: true, type: :uuid, index: {algorithm: :concurrently}
  end
end
