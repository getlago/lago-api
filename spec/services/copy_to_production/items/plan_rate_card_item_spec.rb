# frozen_string_literal: true

require "rails_helper"

RSpec.describe CopyToProduction::Items::PlanRateCardItem do
  subject(:item) { described_class.new(sandbox:, production:) }

  let(:production) { create(:organization) }
  let(:sandbox) { create(:organization, :sandbox, production_organization: production) }
  let(:plan) { create(:catalog_plan, organization: sandbox, code: "pro") }
  let(:category) { create(:product_category, organization: sandbox, code: "compute") }
  let(:product) { create(:product, :fixed, organization: sandbox, product_category: category, code: "seat") }
  let(:rate_card) { create(:rate_card, organization: sandbox, product:, code: "seat_eur") }
  let(:plan_rate_card) { create(:plan_rate_card, organization: sandbox, catalog_plan: plan, rate_card:) }
  let(:live_plan) { create(:catalog_plan, organization: production, code: "pro") }
  let(:live_product) { create(:product, :fixed, :standalone, organization: production, code: "seat") }

  it "answers its item type and activity type" do
    expect(item.item_type).to eq("plan_rate_card")
    expect(item.activity_type).to eq("plan_rate_card.copied_to_production")
  end

  # The plan and the rate card are named by code.
  it_behaves_like "a copy to production item copying every column", PlanRateCard, left_out: %w[catalog_plan_id rate_card_id]
  # The plan rate card and the override are linked by the copy.
  it_behaves_like "a copy to production item copying every column", RatePhase,
    attributes: described_class::PHASE_ATTRIBUTES, left_out: %w[contract_rate_card_id plan_rate_card_id rate_override_id]
  it_behaves_like "a copy to production item copying every column", RateOverride,
    attributes: described_class::RATE_OVERRIDE_ATTRIBUTES

  describe "#find_source" do
    let(:production_plan_rate_card) { create(:plan_rate_card, organization: production) }

    it "finds a plan rate card of the sandbox" do
      expect(item.find_source(plan_rate_card.id)).to eq(plan_rate_card)
    end

    it "ignores a plan rate card of production" do
      expect(item.find_source(production_plan_rate_card.id)).to be_nil
    end
  end

  describe "#find_existing" do
    it "finds nothing without a live plan" do
      expect(item.find_existing(plan_rate_card)).to be_nil
    end

    context "when the live plan has a rate card with the same code" do
      let(:live_plan_rate_card) do
        create(:plan_rate_card, organization: production, catalog_plan: live_plan,
          rate_card: create(:rate_card, organization: production, product: live_product, code: "seat_eur"))
      end

      before { live_plan_rate_card }

      it "finds it" do
        expect(item.find_existing(plan_rate_card)).to eq(live_plan_rate_card)
      end

      context "when it is deleted" do
        before { live_plan_rate_card.discard! }

        it "finds nothing" do
          expect(item.find_existing(plan_rate_card)).to be_nil
        end
      end
    end
  end

  describe "#parent" do
    it "answers its plan" do
      expect(item.parent(plan_rate_card)).to eq(["catalog_plan", plan])
    end
  end

  describe "#dependencies" do
    it "lists the category, the product and the rate card" do
      expect(item.dependencies(plan_rate_card))
        .to eq([["product_category", category], ["product", product], ["rate_card", rate_card]])
    end

    context "when the product is live in its category" do
      before do
        create(:product, :fixed, organization: production, code: "seat",
          product_category: create(:product_category, organization: production, code: "compute"))
      end

      it "leaves the category out" do
        expect(item.dependencies(plan_rate_card)).to eq([["product", product], ["rate_card", rate_card]])
      end
    end

    context "when the product code is live in another category" do
      before { live_product }

      it "keeps the category, as the product is copied" do
        expect(item.dependencies(plan_rate_card))
          .to eq([["product_category", category], ["product", product], ["rate_card", rate_card]])
      end
    end
  end

  describe "#copy!" do
    let(:live_rate_card) { create(:rate_card, organization: production, product: live_product, code: "seat_eur") }
    let(:copy) do
      item.copy!(plan_rate_card, {["catalog_plan", plan.id] => live_plan, ["rate_card", rate_card.id] => live_rate_card})
    end

    before do
      override = create(:rate_override, organization: sandbox, rate_model: "standard", rate_properties: {"amount" => "4"},
        min_amount_cents: 200, billing_interval_count: 1, billing_interval_unit: "month")
      create(:rate_phase, organization: sandbox, plan_rate_card:, code: "default", position: 2)
      create(:rate_phase, organization: sandbox, plan_rate_card:, code: "intro", name: "Intro", position: 1,
        billing_interval_cycle_count: 3, rate_override: override)
      plan_rate_card.update!(units: 5)
    end

    context "with a tiered override" do
      # Stored as the create service saves it: each tier with the lower bound it starts at.
      let(:graduated_ranges) do
        [
          {"from_value" => 0, "to_value" => 10, "flat_amount" => "0", "per_unit_amount" => "1"},
          {"from_value" => 10, "to_value" => nil, "flat_amount" => "0", "per_unit_amount" => "0.5"}
        ]
      end

      before do
        override = create(:rate_override, organization: sandbox, rate_model: "graduated",
          rate_properties: {"graduated_ranges" => graduated_ranges})
        # Between the intro and the indefinite default phase, which must stay last.
        plan_rate_card.rate_phases.find_by!(code: "default").update!(position: 3)
        create(:rate_phase, organization: sandbox, plan_rate_card:, code: "tiers", position: 2, billing_interval_cycle_count: 1,
          rate_override: override)
      end

      it "copies its tiers" do
        expect(copy.rate_phases.find_by!(code: "tiers").rate_override.rate_properties["graduated_ranges"]).to eq(graduated_ranges)
      end
    end

    it "creates it in the live plan with its phases and their overrides" do
      expect(copy).to have_attributes(catalog_plan: live_plan, rate_card: live_rate_card, units: 5, organization_id: production.id)
      expect(copy.rate_phases.map { [it.code, it.name, it.position, it.billing_interval_cycle_count] })
        .to eq([["intro", "Intro", 1, 3], ["default", nil, 2, nil]])
      expect(copy.rate_phases.first.rate_override).to have_attributes(
        organization_id: production.id,
        rate_model: "standard",
        rate_properties: {"amount" => "4"},
        min_amount_cents: 200,
        billing_interval_count: 1,
        billing_interval_unit: "month",
        pricing_unit_conversion_rate: nil
      )
    end

    context "with a rate card priced in a pricing unit", :premium do
      let(:rate_card) { create(:rate_card, organization: sandbox, product:, code: "seat_eur", applied_pricing_unit_code: "credits") }
      let(:live_rate_card) do
        create(:rate_card, organization: production, product: live_product, code: "seat_eur", applied_pricing_unit_code: "credits")
      end

      before do
        create(:pricing_unit, organization: sandbox, code: "credits")
        create(:pricing_unit, organization: production, code: "credits")
        plan_rate_card.rate_phases.find_by!(code: "intro").rate_override.update!(pricing_unit_conversion_rate: 0.25)
      end

      it "copies the conversion rate of its overrides" do
        expect(copy.rate_phases.find_by!(code: "intro").rate_override.pricing_unit_conversion_rate).to eq(0.25)
      end
    end
  end
end
