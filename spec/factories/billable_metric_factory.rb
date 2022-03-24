# frozen_string_literal: true

FactoryBot.define do
  factory :billable_metric do
    organization
    name { 'Some metric' }
    description { 'some description' }
    code { Faker::Name.name.underscore }
    aggregation_type { 'count_agg' }
    properties { {} }
  end
end
