# frozen_string_literal: true

class EnsureOrganizationLastInvoiceGotOrganizationSequentialId < ActiveRecord::Migration[7.2]
  def change
    DataMigrations::InvoicesOrganizationSequentialIdFixerJob.perform_later
  end
end
