class AddReadyForDraftInvoicesRefreshToOrganization < ActiveRecord::Migration[7.0]
  def change
    add_column :organizations, :ready_for_draft_invoices_refresh, :boolean, null: false, default: true
  end
end
