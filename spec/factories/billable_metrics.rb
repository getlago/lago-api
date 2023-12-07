# frozen_string_literal: true

FactoryBot.define do
  factory :billable_metric do
    organization
    name { 'Some metric' }
    description { 'some description' }
    code { Faker::Alphanumeric.alphanumeric(number: 10) }
    aggregation_type { 'count_agg' }
    recurring { false }
    properties { {} }

    trait :recurring do
      recurring { true }
    end
  end

  factory :sum_billable_metric, parent: :billable_metric do
    aggregation_type { 'sum_agg' }
    field_name { 'item_id' }
  end

  factory :latest_billable_metric, parent: :billable_metric do
    aggregation_type { 'latest_agg' }
    field_name { 'item_id' }
  end

  factory :max_billable_metric, parent: :billable_metric do
    aggregation_type { 'max_agg' }
    field_name { 'item_id' }
  end

  factory :weighted_sum_billable_metric, parent: :billable_metric do
    aggregation_type { 'weighted_sum_agg' }
    weighted_interval { 'seconds' }
    field_name { 'value' }
  end

  factory :unique_count_billable_metric, parent: :billable_metric do
    aggregation_type { 'unique_count_agg' }
    field_name { 'item_id' }
  end
end
