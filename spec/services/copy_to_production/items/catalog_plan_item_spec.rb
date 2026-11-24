# frozen_string_literal: true

require "rails_helper"

RSpec.describe CopyToProduction::Items::CatalogPlanItem do
  subject(:item) { described_class.new(sandbox:, production:) }

  let(:production) { create(:organization) }
  let(:sandbox) { create(:organization, :sandbox, production_organization: production) }
  let(:plan) { create(:catalog_plan, organization: sandbox, code: "pro") }

  it "answers its item type and activity type" do
    expect(item.item_type).to eq("catalog_plan")
    expect(item.activity_type).to eq("plan.copied_to_production")
  end

  describe "#find_source" do
    it "finds a catalog plan of the sandbox" do
      expect(item.find_source(plan.id)).to eq(plan)
    end

    it "ignores a catalog plan of production" do
      expect(item.find_source(create(:catalog_plan, organization: production).id)).to be_nil
    end
  end

  describe "#find_existing" do
    let(:live_plan) { create(:catalog_plan, organization: production, code: "pro") }

    before { live_plan }

    it "finds the kept production plan with the same code" do
      expect(item.find_existing(plan)).to eq(live_plan)
    end

    context "when the production plan is deleted" do
      before { live_plan.discard! }

      it "finds nothing" do
        expect(item.find_existing(plan)).to be_nil
      end
    end
  end

  describe "#dependencies" do
    let(:category) { create(:product_category, organization: sandbox, code: "compute") }
    let(:product) { create(:product, :fixed, organization: sandbox, product_category: category, code: "seat") }
    let(:filtered_product) { create(:product, :fixed, :standalone, organization: sandbox, code: "storage") }
    let(:vat) { create(:tax, organization: sandbox, code: "vat") }
    let(:gst) { create(:tax, organization: sandbox, code: "gst") }
    let(:feature) { create(:feature, organization: sandbox, code: "seats") }
    let(:wallet) { create(:plan_wallet, organization: sandbox, catalog_plan: plan) }
    let(:deleted_product) { create(:product, :fixed, :standalone, organization: sandbox, code: "old") }

    before do
      create(:plan_applied_tax, :catalog_plan, organization: sandbox, catalog_plan: plan, tax: vat)
      create(:entitlement, :catalog_plan, organization: sandbox, catalog_plan: plan, feature:)
      create(:catalog_wallet_applied_tax, :plan_level, organization: sandbox, plan_wallet: wallet, tax: gst)
      create(:catalog_wallet_selector, :plan_level, organization: sandbox, plan_wallet: wallet,
        selector_type: "product_filters", fee_type: nil,
        product_filter: create(:product_filter, organization: sandbox, product: filtered_product))
      create(:catalog_wallet_selector, :plan_level, organization: sandbox, plan_wallet: wallet,
        selector_type: "product", fee_type: nil, product: deleted_product)
      create(:plan_wallet_credit_allocation, organization: sandbox, plan_wallet: wallet, product:)
      deleted_product.discard!
    end

    it "lists its taxes, features, then what its wallets reference, without deleted targets" do
      expect(item.dependencies(item.find_source(plan.id))).to eq(
        [
          ["tax", vat], ["feature", feature], ["tax", gst], ["product", filtered_product],
          ["product_category", category], ["product", product]
        ]
      )
    end
  end

  describe "#children" do
    let(:plan_rate_card) do
      create(:plan_rate_card, organization: sandbox, catalog_plan: plan,
        rate_card: create(:rate_card, organization: sandbox, code: "b_card"))
    end
    let(:other_plan_rate_card) do
      create(:plan_rate_card, organization: sandbox, catalog_plan: plan,
        rate_card: create(:rate_card, organization: sandbox, code: "a_card"))
    end

    before do
      plan_rate_card
      other_plan_rate_card
    end

    it "lists its plan rate cards by rate card code" do
      expect(item.children(item.find_source(plan.id)))
        .to eq([["plan_rate_card", other_plan_rate_card], ["plan_rate_card", plan_rate_card]])
    end

    context "when production has a plan with the same code" do
      before { create(:catalog_plan, organization: production, code: "pro") }

      it "lists nothing" do
        expect(item.children(plan)).to eq([])
      end
    end
  end

  describe "#refusal" do
    let(:feature) { create(:feature, organization: sandbox, code: "seats") }
    let(:privilege) { create(:privilege, organization: sandbox, feature:, code: "max") }

    before do
      entitlement = create(:entitlement, :catalog_plan, organization: sandbox, catalog_plan: plan, feature:)
      create(:entitlement_value, organization: sandbox, entitlement:, privilege:, value: "3")
    end

    it "accepts a plan whose features are not live" do
      expect(item.refusal(plan)).to be_nil
    end

    context "when a live feature lacks a privilege of the plan" do
      before { create(:privilege, organization: production, feature: create(:feature, organization: production, code: "seats"), code: "min") }

      it "answers copy_to_production_privilege_missing" do
        expect(item.refusal(plan)).to eq("copy_to_production_privilege_missing")
      end
    end

    context "when a live feature has the privileges of the plan" do
      before { create(:privilege, organization: production, feature: create(:feature, organization: production, code: "seats"), code: "max") }

      it "accepts it" do
        expect(item.refusal(plan)).to be_nil
      end
    end

    context "when a credit allocation targets a filter a live product lacks" do
      let(:product) { create(:product, :fixed, :standalone, organization: sandbox, code: "seat") }

      before do
        create(:product, :fixed, :standalone, organization: production, code: "seat")
        create(:plan_wallet_credit_allocation, organization: sandbox, product: nil,
          plan_wallet: create(:plan_wallet, organization: sandbox, catalog_plan: plan),
          product_filter: create(:product_filter, organization: sandbox, product:, code: "eu"))
      end

      it "answers copy_to_production_filter_missing" do
        expect(item.refusal(plan)).to eq("copy_to_production_filter_missing")
      end
    end

    context "when a wallet only targets deleted products" do
      let(:wallet) { create(:plan_wallet, organization: sandbox, catalog_plan: plan) }
      let(:deleted_product) { create(:product, :fixed, :standalone, organization: sandbox, code: "gpu") }

      before do
        create(:catalog_wallet_selector, :plan_level, organization: sandbox, plan_wallet: wallet,
          selector_type: "product", fee_type: nil, product: deleted_product)
        deleted_product.discard!
      end

      it "answers copy_to_production_target_deleted, as its copy would apply to every fee" do
        expect(item.refusal(plan)).to eq("copy_to_production_target_deleted")
      end

      context "when it also targets a fee type" do
        before { create(:catalog_wallet_selector, :plan_level, organization: sandbox, plan_wallet: wallet) }

        it "accepts it" do
          expect(item.refusal(plan)).to be_nil
        end
      end
    end

    context "with an ongoing balance credit allocation" do
      before do
        create(:plan_wallet_credit_allocation, :ongoing_balance, organization: sandbox,
          plan_wallet: create(:plan_wallet, organization: sandbox, catalog_plan: plan))
      end

      it "accepts it" do
        expect(item.refusal(plan)).to be_nil
      end
    end
  end
end
