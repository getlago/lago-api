# frozen_string_literal: true

require "rails_helper"

RSpec.describe CopyToProduction::Items::CatalogPlanItem do
  subject(:item) { described_class.new(sandbox:, production:) }

  let(:production) { create(:organization) }
  let(:sandbox) { create(:organization, :sandbox, production_organization: production) }
  let(:plan) { create(:catalog_plan, organization: sandbox, code: "pro") }

  it_behaves_like "a copy to production item matched by code", :catalog_plan
  it_behaves_like "a copy to production item copying every column", CatalogPlan

  it "answers its item type and activity type" do
    expect(item.item_type).to eq("catalog_plan")
    expect(item.activity_type).to eq("plan.copied_to_production")
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
  end

  describe "#refusal" do
    it "accepts a plan" do
      expect(item.refusal(plan)).to be_nil
    end

    context "with an entitlement" do
      let(:feature) { create(:feature, organization: sandbox, code: "seats") }
      let(:privilege) { create(:privilege, organization: sandbox, feature:, code: "max", value_type: "integer") }
      let(:live_feature) { create(:feature, organization: production, code: "seats") }
      let(:live_value_type) { "integer" }

      before do
        entitlement = create(:entitlement, :catalog_plan, organization: sandbox, catalog_plan: plan, feature:)
        create(:entitlement_value, organization: sandbox, entitlement:, privilege:, value: "10")
        create(:privilege, organization: production, feature: live_feature, code: "max", value_type: live_value_type)
      end

      it "accepts a live privilege of the same value type" do
        expect(item.refusal(plan)).to be_nil
      end

      context "when the live privilege has another value type" do
        let(:live_value_type) { "string" }

        it "answers copy_to_production_privilege_mismatch" do
          expect(item.refusal(plan)).to eq("copy_to_production_privilege_mismatch")
        end
      end

      context "when the live feature lacks the privilege" do
        before { live_feature.privileges.find_by(code: "max").discard! }

        it "leaves it to the entitlement service" do
          expect(item.refusal(plan)).to be_nil
        end
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
