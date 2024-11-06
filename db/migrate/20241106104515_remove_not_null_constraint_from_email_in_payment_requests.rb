# frozen_string_literal: true

class RemoveNotNullConstraintFromEmailInPaymentRequests < ActiveRecord::Migration[7.1]
  def change
    change_column_null :payment_requests, :email, true
  end
end
