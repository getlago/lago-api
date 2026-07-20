# frozen_string_literal: true

require "rails_helper"

RSpec.describe Chargeable do
  describe ".from_charge" do
    subject(:chargeable) { described_class.from_charge(charge) }

    let(:charge) { create(:standard_charge, pay_in_advance: true, prorated: false) }

    it "maps the charge attributes onto the value object" do
      expect(chargeable).to have_attributes(
        id: charge.id,
        billable_metric: charge.billable_metric,
        charge_model: charge.charge_model,
        properties: charge.properties,
        pay_in_advance: true,
        prorated: false,
        plan: charge.plan,
        accepts_target_wallet: false
      )
    end

    it "reads the accepts_target_wallet attribute from the charge" do
      charge.accepts_target_wallet = true

      expect(chargeable.accepts_target_wallet).to be(true)
    end
  end

  describe "predicates" do
    it "exposes pay_in_advance?, prorated? and dynamic?" do
      chargeable = described_class.new(charge_model: "dynamic", pay_in_advance: true, prorated: true)

      expect(chargeable.pay_in_advance?).to be(true)
      expect(chargeable.prorated?).to be(true)
      expect(chargeable.dynamic?).to be(true)
    end

    it "derives dynamic? from the charge model" do
      expect(described_class.new(charge_model: "standard").dynamic?).to be(false)
      expect(described_class.new(charge_model: :dynamic).dynamic?).to be(true)
    end
  end

  describe "defaults" do
    it "defaults optional attributes so the billing engine can build it partially" do
      chargeable = described_class.new(charge_model: "standard")

      expect(chargeable).to have_attributes(
        id: nil,
        billable_metric: nil,
        properties: {},
        pay_in_advance: false,
        prorated: false,
        plan: nil,
        accepts_target_wallet: false
      )
    end
  end
end
