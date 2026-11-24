# frozen_string_literal: true

FactoryBot.define do
  factory :clickhouse_product_events_enriched, class: "Clickhouse::ProductEventsEnriched" do
    transient do
      organization { create(:organization) }
    end

    organization_id { organization.id }
    external_contract_id { "contract" }
    transaction_id { SecureRandom.uuid }
    timestamp { Time.current.change(usec: 0) }
    enriched_at { Time.current.change(usec: 0) }
    code { "api.requests" }
    properties { {"region" => "eu"} }
    attribution_labels { {} }
    value { "21.0" }
    decimal_value { BigDecimal(value) if value }
  end
end
