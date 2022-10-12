# frozen_string_literal: true

FactoryBot.define do
  factory :billable_metric do
    organization
    name { 'Some metric' }
    description { 'some description' }
    code { Faker::Alphanumeric.alphanumeric(number: 10) }
    aggregation_type { 'count_agg' }
    properties { {} }
  end

  factory :recurring_billable_metric, parent: :billable_metric do
    aggregation_type { 'recurring_count_agg' }
    field_name { 'item_id' }
  end
end
