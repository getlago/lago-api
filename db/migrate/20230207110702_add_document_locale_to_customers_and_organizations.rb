class AddDocumentLocaleToCustomersAndOrganizations < ActiveRecord::Migration[7.0]
  def change
    add_column :organizations, :document_locale, :integer, default: 0, null: false
    add_column :customers, :document_locale, :integer
  end
end
