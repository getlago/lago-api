# frozen_string_literal: true

class AddIndexOnPreciseTotalAmountCents < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!
  def change
    add_index :events, %i[external_subscription_id code timestamp],
      name: 'index_events_on_external_subscription_id_precise_amount',
      where: 'deleted_at IS NULL AND precise_total_amount_cents IS NOT NULL',
      algorithm: :concurrently,
      if_not_exists: true,
      include: %i[organization_id precise_total_amount_cents]
  end
end
