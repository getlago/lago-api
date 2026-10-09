# frozen_string_literal: true

class IndexBillingSegmentsAwaitingInvoicing < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_index :billing_segments, %i[status customer_id],
      where: "status IN ('pending'::billing_segment_status, 'processing'::billing_segment_status)",
      algorithm: :concurrently,
      if_not_exists: true,
      name: "index_billing_segments_on_customer_awaiting_invoicing"
  end
end
