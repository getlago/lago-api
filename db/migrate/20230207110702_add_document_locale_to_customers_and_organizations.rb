# frozen_string_literal: true

class AddDocumentLocaleToCustomersAndOrganizations < ActiveRecord::Migration[7.0]
  def change
    add_column :organizations, :document_locale, :string, default: "en", null: false
    add_column :customers, :document_locale, :string
  end
end
