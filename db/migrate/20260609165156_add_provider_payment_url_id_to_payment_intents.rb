# frozen_string_literal: true

class AddProviderPaymentUrlIdToPaymentIntents < ActiveRecord::Migration[8.0]
  def change
    add_column :payment_intents, :provider_payment_url_id, :string
  end
end
