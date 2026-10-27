# frozen_string_literal: true

require "rails_helper"

RSpec.describe Fees::ResolveCurrentChargeService do
  subject(:result) { described_class.call(subscription:, charge:, charge_filter:) }

  let(:organization) { create(:organization) }
  let(:parent_plan) { create(:plan, organization:) }
  let(:charge) { create(:standard_charge, organization:, plan: parent_plan) }
  let(:charge_filter) { create(:charge_filter, charge:, code: "region_us") }
  let(:subscription_plan) { parent_plan }
  let(:subscription) { create(:subscription, organization:, plan: subscription_plan) }

  context "when the charge is still on the plan" do
    it "returns the same charge and filter" do
      expect(result).to be_success
      expect(result.charge).to eq(charge)
      expect(result.charge_filter).to eq(charge_filter)
    end

    context "without filter" do
      let(:charge_filter) { nil }

      it "returns the same charge and no filter" do
        expect(result.charge).to eq(charge)
        expect(result.charge_filter).to be_nil
      end
    end

    context "with a filter without code" do
      let(:charge_filter) { create(:charge_filter, charge:, code: nil) }

      it "returns the same charge and filter" do
        expect(result.charge).to eq(charge)
        expect(result.charge_filter).to eq(charge_filter)
      end
    end
  end

  context "when the subscription moved to a child plan" do
    let(:subscription_plan) { create(:plan, organization:, parent: parent_plan) }
    let(:child_charge) { create(:standard_charge, organization:, plan: subscription_plan, parent: charge) }
    let!(:child_filter) { create(:charge_filter, charge: child_charge, code: "region_us") }

    before { create(:charge_filter, charge: child_charge, code: "region_eu") }

    it "returns the child charge and the child filter with the same code" do
      expect(result.charge).to eq(child_charge)
      expect(result.charge_filter).to eq(child_filter)
    end

    context "without filter" do
      let(:charge_filter) { nil }

      it "returns the child charge and no filter" do
        expect(result.charge).to eq(child_charge)
        expect(result.charge_filter).to be_nil
      end
    end

    context "when no current filter has the same code" do
      let(:charge_filter) { create(:charge_filter, charge:, code: "region_fr") }

      it "returns no charge and no filter" do
        expect(result.charge).to be_nil
        expect(result.charge_filter).to be_nil
      end
    end

    context "when the filters have no code" do
      let(:charge_filter) { create(:charge_filter, charge:, code: nil) }

      before { create(:charge_filter, charge: child_charge, code: nil) }

      it "returns no charge and no filter" do
        expect(result.charge).to be_nil
        expect(result.charge_filter).to be_nil
      end
    end

    context "when the child filter with the same code is discarded" do
      before { child_filter.discard! }

      it "returns no charge and no filter" do
        expect(result.charge).to be_nil
        expect(result.charge_filter).to be_nil
      end
    end
  end

  context "when the charge is discarded" do
    before { charge.discard! }

    it "returns no charge and no filter" do
      expect(result.charge).to be_nil
      expect(result.charge_filter).to be_nil
    end
  end

  context "when the filter is discarded" do
    before { charge_filter.discard! }

    it "returns no charge and no filter" do
      expect(result.charge).to be_nil
      expect(result.charge_filter).to be_nil
    end
  end

  context "when no current charge matches" do
    let(:subscription_plan) { create(:plan, organization:) }

    before { create(:standard_charge, organization:, plan: subscription_plan) }

    it "returns no charge and no filter" do
      expect(result.charge).to be_nil
      expect(result.charge_filter).to be_nil
    end
  end

  context "without subscription" do
    let(:subscription) { nil }

    it "returns no charge and no filter" do
      expect(result.charge).to be_nil
      expect(result.charge_filter).to be_nil
    end
  end
end
