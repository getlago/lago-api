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
  it { is_expected.to validate_inclusion_of(:pay_in_advance).in_array([true, false]) }
  it { is_expected.to validate_inclusion_of(:prorated).in_array([true, false]) }
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
