# frozen_string_literal: true

FactoryBot.define do
  factory :clickhouse_usage_bucket, class: "Clickhouse::UsageBucket" do
    transient do
      subscription { create(:subscription, customer:) }
      customer { create(:customer) }
      organization { customer.organization }
      billable_metric { create(:billable_metric, organization:) }
      charge { create(:standard_charge, billable_metric:, plan: subscription.plan) }
    end

    organization_id { organization.id }
    subscription_id { subscription.id }
    customer_id { customer.id }
    plan_id { subscription.plan_id }
    code { billable_metric.code }
    target_wallet_code { nil }
    charge_id { charge.id }
    charge_filter_id { "" }
    grouped_by { "{}" }
    aggregation_type { "sum_agg" }
    bucket { Time.current.beginning_of_hour }
    events_count { 1 }
    units { "21.0" }
    last_event_at { Time.current.beginning_of_hour }
    last_ingested_at { Time.current }
    is_deleted { 0 }

    # The RisingWave sink owns every write to usage_buckets_15m, so the model is
    # read-only and `save` would raise. Tests still need rows, so insert around the guard.
    to_create do |usage_bucket|
      Clickhouse::UsageBucket.insert_all([usage_bucket.attributes]) # rubocop:disable Rails/SkipsModelValidations
    end
  end
end
