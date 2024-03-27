# frozen_string_literal: true

FactoryBot.define do
  factory :group do
    billable_metric
    key { "region" }
    value { "europe" }
  end
end
