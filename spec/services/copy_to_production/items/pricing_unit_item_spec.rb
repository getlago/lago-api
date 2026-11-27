# frozen_string_literal: true

require "rails_helper"

RSpec.describe CopyToProduction::Items::PricingUnitItem do
  subject(:item) { described_class.new(sandbox:, production:) }

  let(:production) { create(:organization) }
  let(:sandbox) { create(:organization, :sandbox, production_organization: production) }
  let(:pricing_unit) { create(:pricing_unit, organization: sandbox, code: "credits") }

  it_behaves_like "a copy to production item copying every column", PricingUnit

  it "answers its item type and no activity type" do
    expect(item.item_type).to eq("pricing_unit")
    expect(item.activity_type).to be_nil
  end

  describe "#find_existing" do
    let(:live_pricing_unit) { create(:pricing_unit, organization: production, code: "credits") }

    before { live_pricing_unit }

    it "finds the production pricing unit with the same code" do
      expect(item.find_existing(pricing_unit)).to eq(live_pricing_unit)
    end

    context "when only another organization has the code" do
      let(:live_pricing_unit) { create(:pricing_unit, code: "credits") }

      it "finds nothing" do
        expect(item.find_existing(pricing_unit)).to be_nil
      end
    end
  end

  describe "#copy!", :premium do
    let(:pricing_unit) do
      create(:pricing_unit, organization: sandbox, code: "credits", name: "Credits", short_name: "CR", description: "Prepaid")
    end

    it "creates the pricing unit in production" do
      expect(item.copy!(pricing_unit, {})).to have_attributes(
        organization: production,
        code: "credits",
        name: "Credits",
        short_name: "CR",
        description: "Prepaid"
      )
    end
  end
end
