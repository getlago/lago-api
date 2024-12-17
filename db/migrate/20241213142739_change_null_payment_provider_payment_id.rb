# frozen_string_literal: true

class ChangeNullPaymentProviderPaymentId < ActiveRecord::Migration[7.1]
  def change
    change_column_null :payments, :provider_payment_id, true
  end
end
