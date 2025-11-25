# frozen_string_literal: true

require "rails_helper"

RSpec.describe FixedChargeEvents::Aggregations::PreviewAggregationService do
  subject(:result) { described_class.call(fixed_charge:, subscription:, boundaries:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:) }
  let(:add_on) { create(:add_on, organization:) }
  let(:fixed_charge) do
    create(
      :fixed_charge,
      plan:,
      add_on:,
      charge_model: "standard",
      units: 5,
      properties: {amount: "10"}
    )
  end
  let(:subscription) do
    Subscription.new(
      organization_id: organization.id,
      customer:,
      plan:,
      subscription_at: Time.current,
      started_at: Time.current,
      billing_time: "calendar"
    )
  end
  let(:fixed_charges_from_datetime) { Time.current }
  let(:fixed_charges_to_datetime) { 1.month.from_now }
  let(:boundaries) do
    {
      fixed_charges_from_datetime:,
      fixed_charges_to_datetime:,
      fixed_charges_duration: 30
    }
  end

  it "returns the fixed_charge units" do
    expect(result).to be_success
    expect(result.aggregation).to eq(5)
    expect(result.full_units_number).to eq(5)
  end

  context "when fixed_charge has different units" do
    let(:fixed_charge) do
      create(
        :fixed_charge,
        plan:,
        add_on:,
        charge_model: "graduated",
        units: 15,
        properties: {
          graduated_ranges: [
            {from_value: 0, to_value: 10, flat_amount: "0", per_unit_amount: "1"},
            {from_value: 11, to_value: nil, flat_amount: "0", per_unit_amount: "0.5"}
          ]
        }
      )
    end

    it "returns the fixed_charge units" do
      expect(result).to be_success
      expect(result.aggregation).to eq(15)
      expect(result.full_units_number).to eq(15)
    end
  end

  context "when fixed_charge has zero units" do
    let(:fixed_charge) do
      create(
        :fixed_charge,
        plan:,
        add_on:,
        charge_model: "standard",
        units: 0,
        properties: {amount: "10"}
      )
    end

    it "returns zero" do
      expect(result).to be_success
      expect(result.aggregation).to eq(0)
      expect(result.full_units_number).to eq(0)
    end
  end

  context "when subscription is persisted" do
    let(:subscription) { create(:subscription, organization:, customer:, plan:) }

    it "still returns the fixed_charge units" do
      expect(result).to be_success
      expect(result.aggregation).to eq(5)
      expect(result.full_units_number).to eq(5)
    end
  end
end
