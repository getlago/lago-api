# frozen_string_literal: true

class RemovePaymentProviderNullConstraintOnRefunds < ActiveRecord::Migration[7.0]
  def change
    change_column_null :refunds, :payment_provider_id, true
  end
end
