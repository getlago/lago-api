# frozen_string_literal: true

require "rails_helper"

RSpec.describe Charges::CalculatePriceService do
  subject(:calculate_price_service) do
    described_class.new(
      subscription:,
      units:,
      charge:
    )
  end

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:, amount_cents: 1000) }
  let(:subscription) { create(:subscription, customer:, plan:) }
  let(:billable_metric) { create(:billable_metric, organization:) }
  let(:units) { 5 }

  describe "#call" do
    context "when there is no charge for the billable metric" do
      let(:charge) { nil }

      it "returns only the subscription amount" do
        result = calculate_price_service.call

        expect(result.charge_amount_cents).to eq(0)
        expect(result.subscription_amount_cents).to eq(1000)
        expect(result.total_amount_cents).to eq(1000)
      end
    end

    context "when there is a standard charge" do
      let(:charge) do
        create(:standard_charge,
          plan:,
          billable_metric:,
          properties: {amount: "10"})
      end

      before { charge }

      it "calculates the total amount correctly" do
        result = calculate_price_service.call

        expect(result.charge_amount_cents).to eq(50) # 5 units * 10
        expect(result.subscription_amount_cents).to eq(1000)
        expect(result.total_amount_cents).to eq(1050)
      end
    end

    context "when there is a graduated charge" do
      let(:charge) do
        create(:graduated_charge,
          plan:,
          billable_metric:,
          properties: {
            graduated_ranges: [
              {from_value: 0, to_value: 2, per_unit_amount: "2", flat_amount: "0"},
              {from_value: 3, to_value: nil, per_unit_amount: "3", flat_amount: "0"}
            ]
          })
      end

      before { charge }

      it "calculates the total amount correctly" do
        result = calculate_price_service.call

        # First range: 2 units * 2 = 4
        # Second range: 3 units * 3 = 9
        # Total charge: 13
        expect(result.charge_amount_cents).to eq(13)
        expect(result.subscription_amount_cents).to eq(1000)
        expect(result.total_amount_cents).to eq(1013)
      end
    end

    context "when there is a package charge" do
      let(:charge) do
        create(
          :package_charge,
          plan:,
          billable_metric:,
          properties: {
            package_size: 2,
            amount: "10",
            free_units: 1
          }
        )
      end

      before { charge }

      it "calculates the total amount correctly" do
        result = calculate_price_service.call

        # 5 units - 1 free unit = 4 paid units
        # 4 paid units / 2 package size = 2 packages
        # 2 packages * 10 = 20
        expect(result.charge_amount_cents).to eq(20)
        expect(result.subscription_amount_cents).to eq(1000)
        expect(result.total_amount_cents).to eq(1020)
      end
    end

    context "when there is a volume charge" do
      let(:charge) do
        create(:volume_charge,
          plan:,
          billable_metric:,
          properties: {
            volume_ranges: [
              {from_value: 0, to_value: 2, per_unit_amount: "2", flat_amount: "0"},
              {from_value: 3, to_value: nil, per_unit_amount: "3", flat_amount: "0"}
            ]
          })
      end

      before { charge }

      it "calculates the total amount correctly" do
        result = calculate_price_service.call

        # All 5 units fall into the second range
        # 5 units * 3 = 15
        expect(result.charge_amount_cents).to eq(15)
        expect(result.subscription_amount_cents).to eq(1000)
        expect(result.total_amount_cents).to eq(1015)
      end
    end
  end
end
