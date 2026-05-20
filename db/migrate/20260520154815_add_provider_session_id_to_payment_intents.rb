# frozen_string_literal: true

class AddProviderSessionIdToPaymentIntents < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_column :payment_intents, :provider_session_id, :string
    add_index :payment_intents, :provider_session_id, algorithm: :concurrently
  end
end
