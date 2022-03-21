# frozen_string_literal: true

FactoryBot.define do
  factory :billable_metric do
    organization
    name { 'Some metric' }
    description { 'some description' }
    code { Faker::Name.name }
    billable_period { 'recurring' }
    aggregation_type { 'count_agg' }
    properties { {} }
  end
end
