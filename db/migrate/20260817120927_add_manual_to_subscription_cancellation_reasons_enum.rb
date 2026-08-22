# frozen_string_literal: true

class AddManualToSubscriptionCancellationReasonsEnum < ActiveRecord::Migration[8.0]
  def change
    add_enum_value :subscription_cancellation_reasons, "manual", if_not_exists: true
  end
end
