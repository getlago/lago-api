# frozen_string_literal: true

require "rails_helper"

RSpec.describe FixedCharges::AggregationService, type: :service do
  subject(:aggregation_service) do
    described_class.new(
      fixed_charge:,
      subscription:,
      boundaries:
    )
  end

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:add_on) { create(:add_on, organization:) }
  let(:plan) { create(:plan, organization:) }
  let(:subscription) { create(:subscription, customer:, plan:) }
  let(:fixed_charge) { create(:fixed_charge, add_on:, organization:, plan:) }

  let(:boundaries) do
    {
      charges_from_datetime: Time.zone.parse("2025-03-01").beginning_of_day,
      charges_to_datetime: Time.zone.parse("2025-03-31").end_of_day
    }
  end

  describe "#call" do
    context "when there are no events" do
      it "returns zero aggregation" do
        result = aggregation_service.call

        expect(result.aggregation).to eq(0)
        expect(result.current_usage_units).to eq(0)
        expect(result.full_units_number).to eq(0)
        expect(result.count).to eq(0)
        expect(result.total_aggregated_units).to eq(0)
      end
    end

    context "when there are events" do
      let(:event1) do
        create(
          :event,
          organization:,
          external_subscription_id: subscription.external_id,
          code: add_on.code,
          source: Event.sources[:fixed_charge],
          properties: {units: 5},
          metadata: {fixed_charge_id: fixed_charge.id.to_s},
          timestamp: Time.zone.parse("2025-03-16")
        )
      end

      let(:event2) do
        create(
          :event,
          organization:,
          external_subscription_id: subscription.external_id,
          code: add_on.code,
          source: Event.sources[:fixed_charge],
          properties: {units: 3},
          metadata: {fixed_charge_id: fixed_charge.id.to_s},
          timestamp: Time.zone.parse("2025-03-17")
        )
      end

      before do
        event1
        event2
      end

      it "aggregates the units from events" do
        result = aggregation_service.call

        expect(result.aggregation).to eq(8)
        expect(result.current_usage_units).to eq(8)
        expect(result.full_units_number).to eq(8)
        expect(result.count).to eq(2)
        expect(result.total_aggregated_units).to eq(8)
      end
    end

    context "when there are events outside the boundaries" do
      let(:event_outside) do
        create(
          :event,
          organization:,
          external_subscription_id: subscription.external_id,
          code: add_on.code,
          source: Event.sources[:fixed_charge],
          properties: {units: 10},
          metadata: {fixed_charge_id: fixed_charge.id.to_s},
          timestamp: Time.zone.parse("2025-04-01") # Outside boundaries
        )
      end

      let(:event_inside) do
        create(
          :event,
          organization:,
          external_subscription_id: subscription.external_id,
          code: add_on.code,
          source: Event.sources[:fixed_charge],
          properties: {units: 5},
          metadata: {fixed_charge_id: fixed_charge.id.to_s},
          timestamp: Time.zone.parse("2025-03-16")
        )
      end

      before do
        event_outside
        event_inside
      end

      it "only aggregates events within boundaries" do
        result = aggregation_service.call

        expect(result.aggregation).to eq(5)
        expect(result.count).to eq(1)
      end
    end

    context "when there are events for different fixed charges" do
      let(:other_fixed_charge) { create(:fixed_charge, add_on:, organization:, plan:) }

      let(:event1) do
        create(
          :event,
          organization:,
          external_subscription_id: subscription.external_id,
          code: add_on.code,
          source: Event.sources[:fixed_charge],
          properties: {units: 5},
          metadata: {fixed_charge_id: fixed_charge.id.to_s},
          timestamp: Time.zone.parse("2025-03-16")
        )
      end

      let(:event2) do
        create(
          :event,
          organization:,
          external_subscription_id: subscription.external_id,
          code: add_on.code,
          source: Event.sources[:fixed_charge],
          properties: {units: 3},
          metadata: {fixed_charge_id: other_fixed_charge.id.to_s},
          timestamp: Time.zone.parse("2022-03-16")
        )
      end

      before do
        event1
        event2
      end

      it "only aggregates events for the specific fixed charge" do
        result = aggregation_service.call

        expect(result.aggregation).to eq(5)
        expect(result.count).to eq(1)
      end
    end
  end
end
