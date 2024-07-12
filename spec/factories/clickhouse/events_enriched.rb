# frozen_string_literal: true

FactoryBot.define do
  factory :clickhouse_events_enriched, class: 'Clickhouse::EventsEnriched' do
    transient do
      subscription { create(:subscription, customer:) }
      customer { create(:customer) }
      organization { customer.organization }
      billable_metric { create(:billable_metric, organization:) }
      plan { create(:plan, organization:) }
      charge { create(:standard_charge, billable_metric:, plan:) }
    end

    organization_id { organization.id }
    external_subscription_id { subscription.external_id }
    code { billable_metric.code }
    timestamp { Time.current }
    transaction_id { "tr_#{SecureRandom.hex}" }
    properties { {} }
    value { 21.0 }
    charge_id { charge.id }
    aggregation_type { billable_metric.aggregation_type }
    filters { {} }
    grouped_by { {} }
  end
end
