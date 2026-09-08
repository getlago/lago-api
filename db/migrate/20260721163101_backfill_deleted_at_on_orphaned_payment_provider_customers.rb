# frozen_string_literal: true

class BackfillDeletedAtOnOrphanedPaymentProviderCustomers < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    # Before PaymentProviders::DestroyService soft deleted its provider customers, it only
    # nullified their payment_provider_id, leaving them live (deleted_at IS NULL). A later
    # provider reconnection then created a second live row for the same customer/type, which
    # breaks the exports_customers view. Soft delete those orphaned rows using updated_at, the
    # moment they were nullified, so only the reconnected row stays live.
    PaymentProviderCustomers::BaseCustomer.unscoped
      .where(payment_provider_id: nil, deleted_at: nil)
      .in_batches(of: 1000)
      .update_all("deleted_at = updated_at") # rubocop:disable Rails/SkipsModelValidations
  end

  def down
    # irreversible
  end
end
