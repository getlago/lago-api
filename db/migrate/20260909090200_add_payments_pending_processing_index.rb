# frozen_string_literal: true

class AddPaymentsPendingProcessingIndex < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    # Supports the payment_status filter of the payments list for its rare values
    # (pending, processing) on large organizations, ordered like the list itself.
    # Partial on purpose: the planner cannot pick it for the dominant values, which
    # the (organization_id, created_at DESC, id) cursor index already serves.
    # Four columns like index_invoices_by_cursor: the trailing (created_at DESC, id)
    # is the list ordering, so the page is read without a sort.
    safety_assured do
      add_index :payments,
        [:organization_id, :payable_payment_status, :created_at, :id],
        order: {created_at: :desc, id: :asc},
        where: "payable_payment_status IN ('pending', 'processing')",
        name: "index_payments_on_org_pending_processing_created_at",
        algorithm: :concurrently,
        if_not_exists: true
    end
  end
end
