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
  it { is_expected.to have_many(:events).class_name("FixedChargeEvent").dependent(:destroy) }

  it { is_expected.to validate_numericality_of(:units).is_greater_than_or_equal_to(0) }
  it { is_expected.to validate_presence_of(:charge_model) }
  it { is_expected.to validate_exclusion_of(:pay_in_advance).in_array([nil]) }
  it { is_expected.to validate_exclusion_of(:prorated).in_array([nil]) }
  it { is_expected.to validate_presence_of(:properties) }

  describe "scopes" do
    let(:scoped) { create(:fixed_charge) }
    let(:deleted) { create(:fixed_charge, :deleted) }
    let(:pay_in_advance) { create(:fixed_charge, pay_in_advance: true) }
    let(:pay_in_arrears) { create(:fixed_charge, pay_in_advance: false) }

    before do
      scoped
      deleted
      pay_in_advance
      pay_in_arrears
    end

    describe ".all" do
      it "returns all not deleted fixed charges" do
        expect(described_class.all).to match_array([scoped, pay_in_advance, pay_in_arrears])
      end
    end

    describe ".pay_in_advance" do
      it "returns only pay_in_advance fixed charges" do
        expect(described_class.pay_in_advance).to match_array([pay_in_advance])
      end
    end

    describe ".pay_in_arrears" do
      it "returns only pay_in_arrears fixed charges" do
        expect(described_class.pay_in_arrears).to match_array([pay_in_arrears, scoped])
      end
    end
  end

  describe "#equal_properties?" do
    subject(:equal_properties?) { fixed_charge1.equal_properties?(fixed_charge2) }

    let(:fixed_charge1) do
      build(:fixed_charge, :standard, units: 2, properties: {amount: 100})
    end

    context "when charge model is not the same" do
      let(:fixed_charge2) do
        build(
          :fixed_charge,
          charge_model: :volume,
          properties: fixed_charge1.properties,
          units: fixed_charge1.units
        )
      end

      it { is_expected.to be false }
    end

    context "when properties are different" do
      let(:fixed_charge2) do
        build(
          :fixed_charge,
          charge_model: fixed_charge1.charge_model,
          properties: {amount: 200},
          units: fixed_charge1.units
        )
      end

      it { is_expected.to be false }
    end

    context "when units are different" do
      let(:fixed_charge2) do
        build(
          :fixed_charge,
          charge_model: fixed_charge1.charge_model,
          properties: fixed_charge1.properties,
          units: 99999
        )
      end

      it { is_expected.to be false }
    end

    context "when charge model, properties and units are the same" do
      let(:fixed_charge2) do
        build(
          :fixed_charge,
          charge_model: fixed_charge1.charge_model,
          properties: fixed_charge1.properties,
          units: fixed_charge1.units
        )
      end

      it { is_expected.to be true }
    end
  end

  describe "#validate_pay_in_advance" do
    context "when charge model is standard" do
      it "is valid with pay_in_advance true" do
        fixed_charge = build(:fixed_charge, charge_model: "standard", pay_in_advance: true)
        expect(fixed_charge).to be_valid
      end

      it "is valid with pay_in_advance false" do
        fixed_charge = build(:fixed_charge, charge_model: "standard", pay_in_advance: false)
        expect(fixed_charge).to be_valid
      end
    end

    context "when charge model is volume" do
      it "returns an error with pay_in_advance true" do
        fixed_charge = build(:fixed_charge, :volume, pay_in_advance: true)

        expect(fixed_charge).not_to be_valid
        expect(fixed_charge.errors.messages[:pay_in_advance]).to include("invalid_charge_model")
      end

      it "is valid with pay_in_advance false" do
        fixed_charge = build(:fixed_charge, :volume, pay_in_advance: false)
        expect(fixed_charge).to be_valid
      end
    end

    context "when charge model is graduated" do
      it "is valid with pay_in_advance true" do
        fixed_charge = build(:fixed_charge, :graduated, pay_in_advance: true)
        expect(fixed_charge).to be_valid
      end

      it "is valid with pay_in_advance false" do
        fixed_charge = build(:fixed_charge, :graduated, pay_in_advance: false)
        expect(fixed_charge).to be_valid
      end
    end
  end

  describe "#validate_prorated" do
    context "when charge model is standard" do
      it "is valid with pay_in_advance true and prorated true" do
        fixed_charge = build(:fixed_charge, charge_model: "standard", pay_in_advance: true, prorated: true)
        expect(fixed_charge).to be_valid
      end

      it "is valid with pay_in_advance true and prorated false" do
        fixed_charge = build(:fixed_charge, charge_model: "standard", pay_in_advance: true, prorated: false)
        expect(fixed_charge).to be_valid
      end

      it "is valid with pay_in_advance false and prorated true" do
        fixed_charge = build(:fixed_charge, charge_model: "standard", pay_in_advance: false, prorated: true)
        expect(fixed_charge).to be_valid
      end

      it "is valid with pay_in_advance false and prorated false" do
        fixed_charge = build(:fixed_charge, charge_model: "standard", pay_in_advance: false, prorated: false)
        expect(fixed_charge).to be_valid
      end
    end

    context "when charge model is volume" do
      it "is valid with pay_in_advance false and prorated true" do
        fixed_charge = build(:fixed_charge, :volume, pay_in_advance: false, prorated: true)
        expect(fixed_charge).to be_valid
      end

      it "is valid with pay_in_advance false and prorated false" do
        fixed_charge = build(:fixed_charge, :volume, pay_in_advance: false, prorated: false)
        expect(fixed_charge).to be_valid
      end
    end

    context "when charge model is graduated" do
      it "returns an error with pay_in_advance true and prorated true" do
        fixed_charge = build(:fixed_charge, :graduated, pay_in_advance: true, prorated: true)

        expect(fixed_charge).not_to be_valid
        expect(fixed_charge.errors.messages[:prorated]).to include("invalid_charge_model")
      end

      it "is valid with pay_in_advance true and prorated false" do
        fixed_charge = build(:fixed_charge, :graduated, pay_in_advance: true, prorated: false)
        expect(fixed_charge).to be_valid
      end

      it "is valid with pay_in_advance false and prorated true" do
        fixed_charge = build(:fixed_charge, :graduated, pay_in_advance: false, prorated: true)
        expect(fixed_charge).to be_valid
      end

      it "is valid with pay_in_advance false and prorated false" do
        fixed_charge = build(:fixed_charge, :graduated, pay_in_advance: false, prorated: false)
        expect(fixed_charge).to be_valid
      end
    end
  end
end
