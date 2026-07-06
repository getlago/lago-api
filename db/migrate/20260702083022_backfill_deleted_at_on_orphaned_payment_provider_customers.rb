# frozen_string_literal: true

class BackfillDeletedAtOnOrphanedPaymentProviderCustomers < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    PaymentProviderCustomers::BaseCustomer.unscoped
      .where(payment_provider_id: nil, deleted_at: nil)
      .in_batches(of: 1000)
      .update_all("deleted_at = updated_at") # rubocop:disable Rails/SkipsModelValidations
  end

  def down
    # irreversible
  end
end
