# frozen_string_literal: true

class PopulateInvoicesBillingEntitySequentialId < ActiveRecord::Migration[8.0]
  def up
    PopulateInvoicesBillingEntitySequentialIdJob.perform_later
  end

  def down
    # No down migration needed
  end
end
