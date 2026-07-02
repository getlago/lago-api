# frozen_string_literal: true

class BackfillDeletedAtOnOrphanedPaymentProviderCustomers < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    PaymentProviderCustomers::BaseCustomer.unscoped
      .where(payment_provider_id: nil, deleted_at: nil)
      .find_in_batches(batch_size: 1000) do |batch|
        PaymentProviderCustomers::BaseCustomer.unscoped.where(id: batch.pluck(:id))
          .update_all("deleted_at = updated_at") # rubocop:disable Rails/SkipsModelValidations
      end
  end

  def down
    # irreversible
  end
end
