# frozen_string_literal: true

require "rails_helper"

describe PlanWallets::UpdateService do
  subject(:result) { described_class.call(plan_wallet:, params:) }

  let_it_be(:organization) { create(:organization) }
  let_it_be(:catalog_plan) { create(:catalog_plan, organization:, currency: "USD") }
  let_it_be(:tax) { create(:tax, organization:, code: "vat_20") }
  let_it_be(:product) { create(:product, organization:, code: "api_calls") }

  let(:plan_wallet) do
    create(:plan_wallet, organization:, catalog_plan:, code: "ai_credits", currency: "USD", priority: 10,
      top_up_min_amount_cents: 1000, updated_at: 1.day.ago)
  end
  let(:params) do
    {
      code: "credits",
      name: "Credits",
      invoice_display_name: "Prepaid credits",
      tax_application: "tax_on_purchase",
      priority: 20,
      top_up_min_amount_cents: nil,
      top_up_max_amount_cents: 50_000
    }
  end

  before { allow(Utils::ActivityLog).to receive(:produce).and_call_original }

  it "updates the wallet template's own fields" do
    expect(result).to be_success
    expect(result.plan_wallet.reload).to have_attributes(
      code: "credits",
      name: "Credits",
      invoice_display_name: "Prepaid credits",
      currency: "USD",
      tax_application: "tax_on_purchase",
      priority: 20,
      top_up_min_amount_cents: nil,
      top_up_max_amount_cents: 50_000
    )
  end

  it "logs the update" do
    result

    expect(Utils::ActivityLog).to have_received(:produce).with(plan_wallet, "plan_wallet.updated", after_commit: true)
  end

  context "when the wallet template does not exist" do
    let(:plan_wallet) { nil }

    it "returns a wallet not found failure" do
      expect(result).not_to be_success
      expect(result.error.resource).to eq("wallet")
    end
  end

  context "when another request has deleted the wallet template" do
    subject(:result) { described_class.call(plan_wallet: stale_plan_wallet, params:) }

    let(:stale_plan_wallet) { PlanWallet.find(plan_wallet.id) }

    before do
      stale_plan_wallet
      PlanWallets::DestroyService.call!(plan_wallet:)
    end

    it "returns a wallet not found failure and changes nothing" do
      expect(result).not_to be_success
      expect(result.error.resource).to eq("wallet")
      expect(plan_wallet.reload.code).to eq("ai_credits")
    end
  end

  context "with taxes, a scope and metadata" do
    let(:params) do
      {tax_codes: ["vat_20"], applies_to: {include: [{type: "product", code: "api_calls"}]}, metadata: {team: "growth"}}
    end

    before do
      create(:catalog_wallet_applied_tax, :plan_level, organization:, plan_wallet:)
      create(:catalog_wallet_selector, :plan_level, organization:, plan_wallet:)
      create(:item_metadata, organization:, owner: plan_wallet, value: {"team" => "sales", "tier" => "gold"})
    end

    it "replaces each of them and dates the edit" do
      freeze_time do
        expect(result).to be_success
        expect(plan_wallet.reload.taxes).to eq([tax])
        expect(plan_wallet.selectors.map { [it.selector_type, it.product_id] }).to eq([["product", product.id]])
        expect(plan_wallet.metadata.value).to eq({"team" => "growth"})
        expect(plan_wallet.updated_at).to eq(Time.current)
      end
    end

    context "when they are emptied" do
      let(:params) { {tax_codes: [], applies_to: {include: []}, metadata: nil} }

      it "removes them" do
        expect(result).to be_success
        expect(plan_wallet.reload.taxes).to be_empty
        expect(plan_wallet.selectors).to be_empty
        expect(plan_wallet.metadata).to be_nil
      end
    end

    context "when they are not sent" do
      let(:params) { {priority: 20} }

      it "leaves them as they were" do
        expect(result).to be_success
        expect(plan_wallet.reload.taxes.count).to eq(1)
        expect(plan_wallet.selectors.map(&:selector_type)).to eq(["fee_type"])
        expect(plan_wallet.metadata.value).to eq({"team" => "sales", "tier" => "gold"})
      end
    end

    context "when a selector is refused" do
      let(:params) { {priority: 20, tax_codes: [], applies_to: {include: [{type: "product", code: "unknown"}]}} }

      it "fails on that entry and changes nothing" do
        expect(result).not_to be_success
        expect(result.error.messages).to eq({"applies_to.include[0].code": ["product_not_found"]})
        expect(plan_wallet.reload).to have_attributes(priority: 10, updated_at: be < 1.hour.ago)
        expect(plan_wallet.taxes.count).to eq(1)
      end
    end
  end

  context "when the plan has contracts" do
    before { create(:contract, organization:, catalog_plan:) }

    it "refuses to change the code" do
      expect(result).not_to be_success
      expect(result.error.messages).to eq({code: ["plan_locked"]})
      expect(plan_wallet.reload).to have_attributes(code: "ai_credits", priority: 10)
    end

    context "when the code is sent unchanged" do
      let(:params) { {code: "ai_credits", priority: 20, tax_application: "tax_on_purchase"} }

      it "updates the other fields" do
        expect(result).to be_success
        expect(plan_wallet.reload).to have_attributes(code: "ai_credits", priority: 20, tax_application: "tax_on_purchase")
      end
    end
  end

  describe "refused params" do
    [
      ["a rate amount", {rate_amount: "1.0"}, {rate_amount: ["not_supported"]}],
      ["a currency other than the plan's", {currency: "EUR"}, {currency: ["currency_does_not_match"]}],
      ["a null currency", {currency: nil}, {currency: ["value_is_invalid"]}],
      ["a null code", {code: nil}, {code: ["value_is_mandatory"]}],
      ["a null priority", {priority: nil}, {priority: ["value_is_invalid"]}],
      ["a priority above 50", {priority: 51}, {priority: ["value_is_out_of_range"]}, {priority: {max: 50}}],
      ["metadata that is not an object", {metadata: "growth"}, {metadata: ["value_is_invalid"]}],
      ["a metadata value that is not a string", {metadata: {seats: 5}}, {metadata: ["value_is_invalid"]}],
      ["tax codes that are not a list", {tax_codes: "vat_20"}, {tax_codes: ["value_is_invalid"]}],
      ["an unknown tax application", {tax_application: "tax_free"}, {tax_application: ["value_is_invalid"]}, {tax_application: {allowed_values: %w[tax_on_consumption tax_on_purchase]}}],
      ["a null tax application", {tax_application: nil}, {tax_application: ["value_is_invalid"]}, {tax_application: {allowed_values: %w[tax_on_consumption tax_on_purchase]}}],
      ["a top-up maximum below the minimum", {top_up_min_amount_cents: 1000, top_up_max_amount_cents: 999}, {top_up_max_amount_cents: ["value_is_out_of_range"]}, {top_up_max_amount_cents: {min: 1000}}],
      ["an excluded scope", {applies_to: {exclude: []}}, {"applies_to.exclude": ["not_supported"]}]
    ].each do |description, overrides, messages, meta|
      context "with #{description}" do
        let(:params) { {name: "Credits"}.merge(overrides) }

        it "fails on that field and changes nothing" do
          expect(result).not_to be_success
          expect(result.error.messages).to eq(messages)
          expect(result.error.meta).to eq(meta || {})
          expect(plan_wallet.reload).to have_attributes(name: "Prepaid credits", code: "ai_credits", currency: "USD", priority: 10)
        end
      end
    end

    context "with the code of another wallet template of the plan" do
      let(:params) { {code: "other"} }

      before { create(:plan_wallet, organization:, catalog_plan:, code: "other") }

      it "fails on the code" do
        expect(result).not_to be_success
        expect(result.error.messages).to eq({code: ["value_already_exist"]})
      end
    end

    context "with a tax that does not exist" do
      let(:params) { {priority: 20, tax_codes: ["unknown"]} }

      it "returns a tax not found failure and changes nothing" do
        expect(result).not_to be_success
        expect(result.error.resource).to eq("tax")
        expect(plan_wallet.reload.priority).to eq(10)
      end
    end
  end
end
