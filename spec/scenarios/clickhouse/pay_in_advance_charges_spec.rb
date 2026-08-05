# frozen_string_literal: true

require "rails_helper"

describe "Pay in advance charges Scenarios (Clickhouse)", clickhouse: true, transaction: false do
  let(:organization) { create(:organization, webhook_url: nil, clickhouse_events_store: true) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:, amount_cents: 1000) }
  let(:billable_metric) { create(:billable_metric, organization:, aggregation_type: "count_agg", field_name: nil) }

  # Mirrors the Postgres scenario from spec/scenarios/pay_in_advance_charges_spec.rb:
  # events sharing the same timestamp must each be priced at their own position in
  # the graduated ranges, not all as the last unit of the batch.
  describe "with count_agg / graduated when events share the same timestamp" do
    it "assigns each event its own marginal amount" do
      travel_to(DateTime.new(2023, 1, 24)) do
        create_subscription(
          {
            external_customer_id: customer.external_id,
            external_id: customer.external_id,
            plan_code: plan.code
          }
        )
      end

      charge = create(
        :graduated_charge,
        :pay_in_advance,
        invoiceable: false,
        plan:,
        billable_metric:,
        properties: {
          graduated_ranges: [
            {from_value: 0, to_value: 2, per_unit_amount: "0", flat_amount: "0"},
            {from_value: 3, to_value: nil, per_unit_amount: "2", flat_amount: "0"}
          ]
        }
      )

      subscription = customer.subscriptions.first
      timestamp = Time.zone.parse("2023-02-15 10:00:00.000")

      events = Array.new(3) do
        Events::Common.new(
          organization_id: organization.id,
          transaction_id: SecureRandom.uuid,
          external_subscription_id: subscription.external_id,
          code: billable_metric.code,
          timestamp:,
          properties: {}
        )
      end

      # All events are ingested before any fee is calculated, like a batch ingestion.
      events.each do |event|
        Clickhouse::EventsEnriched.create!(
          transaction_id: event.transaction_id,
          organization_id: organization.id,
          external_subscription_id: subscription.external_id,
          code: billable_metric.code,
          timestamp:,
          properties: {},
          value: "1",
          decimal_value: 1.to_d,
          enriched_at: Time.current
        )
      end

      travel_to(timestamp + 1.second) do
        events.each { |event| Fees::CreatePayInAdvanceService.call!(charge:, event: event.as_json) }
      end

      fees = subscription.fees.where(charge:)
      expect(fees.map(&:pay_in_advance_event_transaction_id)).to match_array(events.map(&:transaction_id))
      expect(fees.map(&:units)).to all(eq(1))
      expect(fees.map(&:amount_cents).sort).to eq([0, 0, 200])
    end
  end
end
