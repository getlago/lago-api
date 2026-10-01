# frozen_string_literal: true

class AddX402ToPaymentType < ActiveRecord::Migration[8.0]
  def change
    add_enum_value :payment_type, "x402", if_not_exists: true
  end
end
