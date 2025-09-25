# frozen_string_literal: true

require "rails_helper"

RSpec.describe FixedCharge do
  subject { build(:fixed_charge) }

  it_behaves_like "paper_trail traceable"

  it { expect(described_class).to be_soft_deletable }
  it { is_expected.to belong_to(:organization) }
  it { is_expected.to belong_to(:plan) }
  it { is_expected.to belong_to(:add_on) }
  it { is_expected.to belong_to(:parent).class_name("FixedCharge").optional }
  it { is_expected.to have_many(:children).class_name("FixedCharge").dependent(:nullify) }
  it { is_expected.to have_many(:applied_taxes).class_name("FixedCharge::AppliedTax").dependent(:destroy) }
  it { is_expected.to have_many(:taxes).through(:applied_taxes) }
  it { is_expected.to have_many(:fees) }

  it { is_expected.to validate_numericality_of(:units).is_greater_than_or_equal_to(0) }
  it { is_expected.to validate_presence_of(:charge_model) }
  it { is_expected.to validate_exclusion_of(:pay_in_advance).in_array([nil]) }
  it { is_expected.to validate_exclusion_of(:prorated).in_array([nil]) }
  it { is_expected.to validate_presence_of(:properties) }

  describe "#equal_properties?" do
    let(:fixed_charge1) { build(:fixed_charge, properties: {amount: 100}) }

    context "when charge model is not the same" do
      let(:fixed_charge2) { build(:fixed_charge, :volume) }

      it "returns false" do
        expect(fixed_charge1.equal_properties?(fixed_charge2)).to be false
      end
    end

    context "when charge model is the same and properties are different" do
      let(:fixed_charge2) { build(:fixed_charge, properties: {amount: 200}) }

      it "returns false if properties are not the same" do
        expect(fixed_charge1.equal_properties?(fixed_charge2)).to be false
      end
    end

    context "when charge model and properties are the same" do
      let(:fixed_charge2) { build(:fixed_charge, properties: {amount: 100}) }

      it "returns true if both charge model and properties are the same" do
        expect(fixed_charge1.equal_properties?(fixed_charge2)).to be true
      end
    end
  end

  describe "#included_in_next_subscription?" do
    let(:add_on) { build(:add_on) }
    let(:fixed_charge) { build(:fixed_charge, add_on:) }
    let(:subscription) { create(:subscription, plan: fixed_charge.plan) }
    let(:next_subscription) { create(:subscription, :with_previous_subscription, previous_subscription: subscription) }

    context "when the fixed charge is included in the next subscription" do
      before { next_subscription.plan.fixed_charges = [fixed_charge] }

      it "returns true" do
        expect(fixed_charge.included_in_next_subscription?(subscription)).to be true
      end
    end

    context "when the fixed charge is not included in the next subscription" do
      before { next_subscription.plan.fixed_charges = [] }

      it "returns false" do
        expect(fixed_charge.included_in_next_subscription?(subscription)).to be false
      end
    end
  end
end
