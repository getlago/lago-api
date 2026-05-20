# frozen_string_literal: true

require "rails_helper"

RSpec.describe FixedChargeForSubscription do
  subject(:presenter) { described_class.new(fixed_charge, subscription) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:) }
  let(:fixed_charge) { create(:fixed_charge, plan:, organization:, units: 10) }
  let(:subscription) { create(:subscription, plan:, customer:) }

  describe "#units" do
    context "without a per-subscription override" do
      it "returns the plan-level units from the wrapped FixedCharge" do
        expect(presenter.units).to eq(fixed_charge.units)
      end
    end

    context "with a per-subscription override" do
      before do
        create(:subscription_fixed_charge_units_override,
          subscription:,
          fixed_charge:,
          organization:,
          billing_entity: customer.billing_entity,
          units: 42)
      end

      it "returns the overridden units" do
        expect(presenter.units).to eq(42)
      end
    end
  end

  describe "delegation" do
    it "delegates other attribute reads to the wrapped FixedCharge" do
      expect(presenter.id).to eq(fixed_charge.id)
      expect(presenter.code).to eq(fixed_charge.code)
      expect(presenter.charge_model).to eq(fixed_charge.charge_model)
      expect(presenter.pay_in_advance).to eq(fixed_charge.pay_in_advance)
      expect(presenter.add_on_id).to eq(fixed_charge.add_on_id)
    end
  end
end
