# frozen_string_literal: true

FactoryBot.define do
  factory :charge_filter_value do
    charge_filter
    billable_metric_filter
    value { Faker::Lorem.word }
  end
end
