# frozen_string_literal: true

class AddOrganizationIdToInvoices < ActiveRecord::Migration[7.0]
  def change
    add_reference :invoices, :organization, type: :uuid, foreign_key: true, index: true, null: true

    reversible do |dir|
      dir.up do
        LagoApi::Application.load_tasks
        Rake::Task['invoices:fill_organization'].invoke
      end
    end

    change_column_null :invoices, :organization_id, false
  end
end
