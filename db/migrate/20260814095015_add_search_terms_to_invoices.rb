# frozen_string_literal: true

class AddSearchTermsToInvoices < ActiveRecord::Migration[8.0]
  def change
    add_column :invoices, :search_terms, :text
  end
end
