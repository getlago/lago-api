# frozen_string_literal: true

module Types
  module Plans
    class BillingPeriodEnum < Types::BaseEnum
      Plan::BILLING_PERIODS.each do |type|
        value type
      end
    end
  end
end
