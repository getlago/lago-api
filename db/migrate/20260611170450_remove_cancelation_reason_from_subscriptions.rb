# frozen_string_literal: true

class RemoveCancelationReasonFromSubscriptions < ActiveRecord::Migration[8.0]
  def change
    safety_assured do
      remove_column :subscriptions, :cancelation_reason, :subscription_cancelation_reasons
      drop_enum :subscription_cancelation_reasons, %w[payment_failed timeout]
    end
  end
end
