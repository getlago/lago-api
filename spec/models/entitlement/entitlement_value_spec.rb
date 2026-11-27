# frozen_string_literal: true

require "rails_helper"

RSpec.describe Entitlement::EntitlementValue do
  subject { create(:entitlement_value) }

  let_it_be(:organization) { create_default(:organization) }
  let_it_be(:plan) { create_default(:plan) }

  it { expect(described_class).to be_soft_deletable }

  describe "associations" do
    it do
      expect(subject).to belong_to(:organization)
      expect(subject).to belong_to(:privilege).class_name("Entitlement::Privilege")
      expect(subject).to belong_to(:entitlement).class_name("Entitlement::Entitlement")
    end
  end

  describe "validations" do
    it do
      expect(subject).to validate_presence_of(:entitlement_privilege_id)
      expect(subject).to validate_presence_of(:entitlement_entitlement_id)
      expect(subject).to validate_presence_of(:value)
    end
  end

  describe ".read_value" do
    it "reads a legacy boolean as a word" do
      expect(described_class.read_value("t", "boolean")).to eq("true")
      expect(described_class.read_value("f", "boolean")).to eq("false")
      expect(described_class.read_value("true", "boolean")).to eq("true")
    end

    it "leaves the values of other types" do
      expect(described_class.read_value("t", "string")).to eq("t")
    end
  end

  describe "#value" do
    subject(:entitlement_value) { create(:entitlement_value, privilege:, value: "t") }

    let(:privilege) { create(:privilege, value_type: "boolean") }

    it "reads a boolean stored as t as a word" do
      expect(entitlement_value.value).to eq("true")
      expect(entitlement_value.read_attribute(:value)).to eq("t")
    end

    context "when the privilege is a string" do
      let(:privilege) { create(:privilege, value_type: "string") }

      it "returns the stored value" do
        expect(entitlement_value.value).to eq("t")
      end
    end
  end
end
