# frozen_string_literal: true

require "rails_helper"

RSpec.describe Fees::FixedChargeService, type: :service do
  subject(:fixed_charge_service) do
    described_class.new(
      invoice:,
      fixed_charge:,
      subscription:,
      boundaries:,
      context:
    )
  end

  let(:organization) { create(:organization) }
  let(:billing_entity) { create(:billing_entity, organization:) }
  let(:customer) { create(:customer, billing_entity:, organization:) }
  let(:context) { :finalize }

  let(:subscription) do
    create(
      :subscription,
      status: :active,
      started_at: Time.zone.parse("2022-03-15"),
      customer:,
      organization:
    )
  end

  let(:boundaries) do
    {
      from_datetime: subscription.started_at.to_date.beginning_of_day,
      to_datetime: subscription.started_at.end_of_month.end_of_day,
      charges_from_datetime: subscription.started_at.beginning_of_day,
      charges_to_datetime: subscription.started_at.end_of_month.end_of_day,
      timestamp: subscription.started_at.end_of_month.end_of_day + 1.second,
      charges_duration: (
        subscription.started_at.end_of_month.end_of_day - subscription.started_at.beginning_of_month
      ).fdiv(1.day).ceil
    }
  end

  let(:invoice) do
    create(:invoice, customer:, organization:)
  end

  let(:fixed_charge) do
    create(
      :fixed_charge,
      plan: subscription.plan,
      properties: {amount: "20"},
      organization:
    )
  end

  describe "#call" do
    context "when there are events for the fixed charge" do
      let(:event1) do
        create(
          :event,
          organization:,
          external_subscription_id: subscription.external_id,
          code: fixed_charge.add_on.code,
          source: Event.sources[:fixed_charge],
          properties: {units: 2},
          metadata: {fixed_charge_id: fixed_charge.id.to_s},
          timestamp: Time.zone.parse("2022-03-16")
        )
      end

      let(:event2) do
        create(
          :event,
          organization:,
          external_subscription_id: subscription.external_id,
          code: fixed_charge.add_on.code,
          source: Event.sources[:fixed_charge],
          properties: {units: 3},
          metadata: {fixed_charge_id: fixed_charge.id.to_s},
          timestamp: Time.zone.parse("2022-03-17")
        )
      end

      before do
        event1
        event2
      end

      it "creates a fee based on aggregated events" do
        result = fixed_charge_service.call

        expect(result).to be_success
        expect(result.fees.count).to eq(1)

        fee = result.fees.first
        expect(fee).to have_attributes(
          fixed_charge:,
          invoice:,
          subscription:,
          fee_type: "fixed_charge",
          units: 5, # 2 + 3 from events
          amount_cents: 10000, # 5 * 20 * 100
          amount_currency: subscription.plan.amount_currency,
          organization_id: organization.id,
          billing_entity_id: billing_entity.id,
          events_count: 2
        )
      end
    end

    context "when there are no events for the fixed charge" do
      it "does not create a fee" do
        expect { fixed_charge_service.call }.not_to change(Fee, :count)

        result = fixed_charge_service.call
        expect(result).to be_success
        expect(result.fees.count).to be_zero
      end
    end

    context "when there are events outside the boundaries" do
      let(:event_outside) do
        create(
          :event,
          organization:,
          external_subscription_id: subscription.external_id,
          code: fixed_charge.add_on.code,
          source: Event.sources[:fixed_charge],
          properties: {units: 10},
          metadata: {fixed_charge_id: fixed_charge.id.to_s},
          timestamp: Time.zone.parse("2022-04-01") # Outside boundaries
        )
      end

      before do
        event_outside
      end

      it "does not create a fee" do
        expect { fixed_charge_service.call }.not_to change(Fee, :count)

        result = fixed_charge_service.call
        expect(result).to be_success
        expect(result.fees.count).to be_zero
      end
    end

    context "when there are events for different fixed charges" do
      let(:other_fixed_charge) { create(:fixed_charge, add_on: fixed_charge.add_on, organization:) }

      let(:event_other) do
        create(
          :event,
          organization:,
          external_subscription_id: subscription.external_id,
          code: fixed_charge.add_on.code,
          source: Event.sources[:fixed_charge],
          properties: {units: 10},
          metadata: {fixed_charge_id: other_fixed_charge.id.to_s},
          timestamp: Time.zone.parse("2022-03-16")
        )
      end

      before do
        event_other
      end

      it "does not create a fee" do
        expect { fixed_charge_service.call }.not_to change(Fee, :count)
      end
    end

    context "with graduated charge model" do
      let(:fixed_charge) do
        create(
          :fixed_charge,
          plan: subscription.plan,
          charge_model: "graduated",
          properties: {
            graduated_ranges: [
              {from_value: 0, to_value: 10, per_unit_amount: "2", flat_amount: "1"},
              {from_value: 11, to_value: nil, per_unit_amount: "1", flat_amount: "0"}
            ]
          },
          organization:
        )
      end

      let(:event1) do
        create(
          :event,
          organization:,
          external_subscription_id: subscription.external_id,
          code: fixed_charge.add_on.code,
          source: Event.sources[:fixed_charge],
          properties: {units: 5},
          metadata: {fixed_charge_id: fixed_charge.id.to_s},
          timestamp: Time.zone.parse("2022-03-16")
        )
      end

      let(:event2) do
        create(
          :event,
          organization:,
          external_subscription_id: subscription.external_id,
          code: fixed_charge.add_on.code,
          source: Event.sources[:fixed_charge],
          properties: {units: 11},
          metadata: {fixed_charge_id: fixed_charge.id.to_s},
          timestamp: Time.zone.parse("2022-03-17")
        )
      end

      before do
        event1
        event2
      end

      it "creates a fee with graduated calculation" do
        result = fixed_charge_service.call

        expect(result).to be_success
        # 16 units total: 10 in first range (10 * 2 + 1 = 21) + 6 in second range (6 * 1 = 6) = 27
        expect(result.fees.first.amount_cents).to eq(2700)
      end
    end

    context "with volume charge model" do
      let(:fixed_charge) do
        create(
          :fixed_charge,
          plan: subscription.plan,
          charge_model: "volume",
          properties: {
            volume_ranges: [
              {from_value: 0, to_value: 100, per_unit_amount: "2", flat_amount: "10"},
              {from_value: 101, to_value: 200, per_unit_amount: "1", flat_amount: "15"},
              {from_value: 201, to_value: nil, per_unit_amount: "0.5", flat_amount: "50"}
            ]
          },
          organization:
        )
      end

      let(:event1) do
        create(
          :event,
          organization:,
          external_subscription_id: subscription.external_id,
          code: fixed_charge.add_on.code,
          source: Event.sources[:fixed_charge],
          properties: {units: 50},
          metadata: {fixed_charge_id: fixed_charge.id.to_s},
          timestamp: Time.zone.parse("2022-03-16")
        )
      end

      let(:event2) do
        create(
          :event,
          organization:,
          external_subscription_id: subscription.external_id,
          code: fixed_charge.add_on.code,
          source: Event.sources[:fixed_charge],
          properties: {units: 60},
          metadata: {fixed_charge_id: fixed_charge.id.to_s},
          timestamp: Time.zone.parse("2022-03-17")
        )
      end

      before do
        event1
        event2
      end

      it "creates a fee with volume calculation" do
        result = fixed_charge_service.call

        expect(result).to be_success
        # 110 units total: falls into second tier (101-200), so all 110 units charged at $1 each + $15 flat = $125
        expect(result.fees.first.amount_cents).to eq(12500)
      end
    end

    context "when fee already exists" do
      let(:invoice) { create(:invoice, organization:) }

      let(:existing_fee) do
        create(
          :fee,
          fixed_charge:,
          invoice:,
          subscription:,
          fee_type: :fixed_charge,
          properties: boundaries
        )
      end

      before do
        existing_fee
      end

      it "does not create a new fee" do
        expect { fixed_charge_service.call }.not_to change(Fee, :count)
      end

      it "returns existing fees" do
        result = fixed_charge_service.call

        expect(result).to be_success
        expect(result.fees).to eq([existing_fee])
      end
    end
  end
end
