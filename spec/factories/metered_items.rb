# frozen_string_literal: true

FactoryBot.define do
  factory :metered_item, class: "Fees::ChargeService::MeteredItem" do
    skip_create

    transient do
      charge { build(:standard_charge) }
      billing_segment { nil }
      boundaries do
        BillingPeriodBoundaries.new(
          from_datetime: Time.current.beginning_of_month,
          to_datetime: Time.current.end_of_month,
          charges_from_datetime: Time.current.beginning_of_month,
          charges_to_datetime: Time.current.end_of_month,
          charges_duration: Time.current.end_of_month.day,
          timestamp: Time.current
        )
      end
      event { nil }
    end

    initialize_with do
      if billing_segment
        Fees::ChargeService::MeteredItem.from_billing_segment(billing_segment:, event:)
      else
        Fees::ChargeService::MeteredItem.from_charge(charge:, boundaries:, event:)
      end
    end
  end
end
