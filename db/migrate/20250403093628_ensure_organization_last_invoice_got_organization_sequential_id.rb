class EnsureOrganizationLastInvoiceGotOrganizationSequentialId < ActiveRecord::Migration[7.2]
  def change
    Migrations::InvoicesOrganizationSequentialIdFixer.call
  end
end
