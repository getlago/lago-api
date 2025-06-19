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

  let(:customer) { create(:customer) }
  let(:organization) { customer.organization }
  let(:context) { :finalize }

  let(:subscription) do
    create(
      :subscription,
      status: :active,
      started_at: Time.zone.parse("2022-03-15"),
      customer:
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
      properties: {amount: "20"}
    )
  end

  before do
    fixed_charge
  end

  describe "#call" do
    it "creates a fixed charge fee" do
      result = fixed_charge_service.call

      aggregate_failures do
        expect(result).to be_success
        expect(result.fees.count).to eq(1)

        fee = result.fees.first
        expect(fee).to have_attributes(
          subscription:,
          fixed_charge:,
          fee_type: "fixed_charge",
          units: 1,
          amount_cents: 2000,
          amount_currency: subscription.plan.amount_currency
        )
      end
    end

    context "when fixed charge has zero units" do
      before do
        fixed_charge.update!(untis: 0)
      end

      it "does not create a fee" do
        result = fixed_charge_service.call

        expect(result).to be_success
        expect(result.fees.count).to eq(0)
      end
    end

    context "when subscription has units override" do
      before do
        create(:subscriptions_units_override, subscription:, fixed_charge:, units: 3)
      end

      it "creates a fee with override units" do
        result = fixed_charge_service.call

        expect(result).to be_success
        expect(result.fees.first.units).to eq(3)
        expect(result.fees.first.amount_cents).to eq(6000)
      end
    end

    context "when fee already exists" do
      before do
        create(:fee, subscription:, fixed_charge:, invoice:, fee_type: :fixed_charge)
      end

      it "does not create a new fee" do
        result = fixed_charge_service.call

        expect(result).to be_success
        expect(result.fees.count).to eq(0)
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
          }
        )
      end

      it "creates a fee with graduated calculation" do
        result = fixed_charge_service.call

        expect(result).to be_success
        expect(result.fees.first.amount_cents).to eq(1100) # 1 * 2 + 1 = 3, then * 100 for cents
      end
    end
  end
end 