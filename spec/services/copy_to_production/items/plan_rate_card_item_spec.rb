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

  describe "#find_source" do
    it "finds a plan rate card of the sandbox" do
      expect(item.find_source(plan_rate_card.id)).to eq(plan_rate_card)
    end

    it "ignores a plan rate card of production" do
      expect(item.find_source(create(:plan_rate_card, organization: production).id)).to be_nil
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

  describe "#parents" do
    it "answers its plan" do
      expect(item.parents(plan_rate_card)).to eq([["catalog_plan", plan]])
    end
  end

  describe "#dependencies" do
    it "lists the category, the product and the rate card" do
      expect(item.dependencies(plan_rate_card))
        .to eq([["product_category", category], ["product", product], ["rate_card", rate_card]])
    end

    context "when the product is live" do
      before { live_product }

      it "leaves the category out" do
        expect(item.dependencies(plan_rate_card)).to eq([["product", product], ["rate_card", rate_card]])
      end
    end
  end

  describe "#refusal" do
    it "accepts a plan rate card whose plan is not live" do
      expect(item.refusal(plan_rate_card)).to be_nil
    end

    context "when the live plan prices the product with another rate card" do
      before do
        create(:plan_rate_card, organization: production, catalog_plan: live_plan,
          rate_card: create(:rate_card, organization: production, product: live_product, code: "seat_eur_v2"))
      end

      it "answers copy_to_production_already_priced" do
        expect(item.refusal(plan_rate_card)).to eq("copy_to_production_already_priced")
      end
    end

    context "when the live plan prices another filter of the product" do
      before do
        create(:plan_rate_card, organization: production, catalog_plan: live_plan,
          rate_card: create(:rate_card, :with_filter, organization: production, product: live_product, code: "seat_eu"))
      end

      it "accepts it" do
        expect(item.refusal(plan_rate_card)).to be_nil
      end
    end

    context "when the live plan has contracts" do
      before { create(:contract, :terminated, customer: create(:customer, organization: production), catalog_plan: live_plan) }

      it "answers plan_locked" do
        expect(item.refusal(plan_rate_card)).to eq("plan_locked")
      end
    end
  end

  describe "#active_subscriptions_count" do
    it "answers nil without a live plan" do
      expect(item.active_subscriptions_count(plan_rate_card)).to be_nil
    end

    context "when the plan is live" do
      before do
        customer = create(:customer, organization: production)
        create(:contract, customer:, catalog_plan: live_plan)
        create(:contract, :pending, customer:, catalog_plan: live_plan)
        create(:contract, :terminated, customer:, catalog_plan: live_plan)
      end

      it "counts its active contracts" do
        expect(item.active_subscriptions_count(plan_rate_card)).to eq(1)
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
        min_amount_cents: 0)
      create(:rate_phase, organization: sandbox, plan_rate_card:, code: "default", position: 2)
      create(:rate_phase, organization: sandbox, plan_rate_card:, code: "intro", name: "Intro", position: 1,
        billing_interval_cycle_count: 3, rate_override: override)
      plan_rate_card.update!(units: 5)
    end

    it "creates it in the live plan with its phases and their overrides" do
      expect(copy).to have_attributes(catalog_plan: live_plan, rate_card: live_rate_card, units: 5, organization_id: production.id)
      expect(copy.rate_phases.map { [it.code, it.name, it.position, it.billing_interval_cycle_count] })
        .to eq([["intro", "Intro", 1, 3], ["default", nil, 2, nil]])
      expect(copy.rate_phases.first.rate_override)
        .to have_attributes(organization_id: production.id, rate_model: "standard", rate_properties: {"amount" => "4"})
    end
  end
end
