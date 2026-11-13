# frozen_string_literal: true

require "rails_helper"

describe PlanWallets::CreateService do
  subject(:result) { described_class.call(catalog_plan:, params:) }

  let_it_be(:organization) { create(:organization) }
  let_it_be(:catalog_plan) { create(:catalog_plan, organization:, currency: "USD") }
  let_it_be(:tax) { create(:tax, organization:, code: "vat_20") }
  let_it_be(:product) { create(:product, organization:, code: "api_calls") }

  let(:params) do
    {
      code: "ai_credits",
      name: "AI credits",
      invoice_display_name: "Prepaid credits",
      currency: "USD",
      tax_application: "tax_on_purchase",
      tax_codes: ["vat_20"],
      applies_to: {include: [{type: "fee_type", code: "metered"}, {type: "product", code: "api_calls"}]},
      priority: 10,
      top_up_min_amount_cents: 1000,
      top_up_max_amount_cents: 50_000,
      metadata: {team: "growth"}
    }
  end

  before { allow(Utils::ActivityLog).to receive(:produce).and_call_original }

  it "creates the wallet template with its taxes, scope and metadata" do
    expect { result }.to change(catalog_plan.wallets, :count).by(1)

    expect(result).to be_success
    expect(result.plan_wallet).to have_attributes(
      organization_id: organization.id,
      catalog_plan_id: catalog_plan.id,
      code: "ai_credits",
      name: "AI credits",
      invoice_display_name: "Prepaid credits",
      currency: "USD",
      tax_application: "tax_on_purchase",
      priority: 10,
      top_up_min_amount_cents: 1000,
      top_up_max_amount_cents: 50_000
    )
    expect(result.plan_wallet.taxes).to eq([tax])
    expect(result.plan_wallet.selectors.map { [it.selector_type, it.fee_type, it.product_id] })
      .to match_array([["fee_type", "metered", nil], ["product", nil, product.id]])
    expect(result.plan_wallet.metadata.value).to eq({"team" => "growth"})
  end

  it "logs the creation" do
    result

    expect(Utils::ActivityLog).to have_received(:produce).with(result.plan_wallet, "plan_wallet.created", after_commit: true)
  end

  context "with only the required fields" do
    let(:params) { {code: "ai_credits", currency: "USD"} }

    it "creates an untaxed wallet template open to every fee, with the defaults" do
      expect(result).to be_success
      expect(result.plan_wallet).to have_attributes(
        name: nil, tax_application: "tax_on_consumption", priority: 50, top_up_min_amount_cents: nil, top_up_max_amount_cents: nil
      )
      expect(result.plan_wallet.taxes).to be_empty
      expect(result.plan_wallet.selectors).to be_empty
      expect(result.plan_wallet.metadata).to be_nil
    end
  end

  context "when the top-up limits are equal" do
    let(:params) { {code: "ai_credits", currency: "USD", top_up_min_amount_cents: 1000, top_up_max_amount_cents: 1000} }

    it "creates the wallet template" do
      expect(result).to be_success
    end
  end

  context "when the plan does not exist" do
    let(:catalog_plan) { nil }

    it "returns a plan not found failure" do
      expect(result).not_to be_success
      expect(result.error.resource).to eq("plan")
    end
  end

  context "when the plan already has contracts" do
    before { create(:contract, organization:, catalog_plan:) }

    it "still creates the wallet template" do
      expect(result).to be_success
    end
  end

  describe "refused params" do
    [
      ["a rate amount", {rate_amount: "1.0"}, {rate_amount: ["not_supported"]}],
      ["a currency other than the plan's", {currency: "EUR"}, {currency: ["currency_does_not_match"]}],
      ["no currency", {currency: nil}, {currency: ["value_is_invalid"]}],
      ["no code", {code: nil}, {code: ["value_is_mandatory"]}],
      ["a code that is not URL safe", {code: "ai credits"}, {code: ["value_is_invalid"]}],
      ["an unknown tax application", {tax_application: "tax_free"}, {tax_application: ["value_is_invalid"]}, {tax_application: {allowed_values: %w[tax_on_consumption tax_on_purchase]}}],
      ["a priority below 1", {priority: 0}, {priority: ["value_is_out_of_range"]}, {priority: {min: 1}}],
      ["a priority above 50", {priority: 51}, {priority: ["value_is_out_of_range"]}, {priority: {max: 50}}],
      ["a priority that is not a number", {priority: "high"}, {priority: ["value_is_invalid"]}],
      ["a negative top-up minimum", {top_up_min_amount_cents: -1}, {top_up_min_amount_cents: ["value_is_out_of_range"]}, {top_up_min_amount_cents: {min: 0}}],
      ["a fractional top-up maximum", {top_up_max_amount_cents: 60_000.5}, {top_up_max_amount_cents: ["value_is_invalid"]}],
      ["a top-up minimum that is not a number", {top_up_min_amount_cents: "ten"}, {top_up_min_amount_cents: ["value_is_invalid"]}],
      ["a top-up minimum above the maximum", {top_up_min_amount_cents: 50_001}, {top_up_max_amount_cents: ["value_is_out_of_range"]}, {top_up_max_amount_cents: {min: 50_001}}],
      ["an excluded scope", {applies_to: {exclude: [{type: "fee_type", code: "fixed"}]}}, {"applies_to.exclude": ["not_supported"]}],
      ["a selector that does not exist", {applies_to: {include: [{type: "product", code: "unknown"}]}}, {"applies_to.include[0].code": ["product_not_found"]}]
    ].each do |description, overrides, messages, meta|
      context "with #{description}" do
        let(:params) { super().merge(overrides) }

        it "fails on that field and writes nothing" do
          expect { result }.not_to change { [PlanWallet.count, CatalogWalletAppliedTax.count, CatalogWalletSelector.count, Metadata::ItemMetadata.count] }

          expect(result).not_to be_success
          expect(result.error.messages).to eq(messages)
          expect(result.error.meta).to eq(meta || {})
        end
      end
    end

    context "with a tax that does not exist" do
      let(:params) { super().merge(tax_codes: %w[vat_20 unknown]) }

      it "returns a tax not found failure and writes nothing" do
        expect { result }.not_to change { [PlanWallet.count, CatalogWalletAppliedTax.count] }

        expect(result).not_to be_success
        expect(result.error.resource).to eq("tax")
      end
    end
  end

  context "when the plan already has a wallet template with that code" do
    before { create(:plan_wallet, organization:, catalog_plan:, code: "ai_credits") }

    it "fails on the code" do
      expect(result).not_to be_success
      expect(result.error.messages).to eq({code: ["value_already_exist"]})
    end

    context "when that wallet template is deleted" do
      before { catalog_plan.wallets.find_by(code: "ai_credits").discard! }

      it "creates the wallet template" do
        expect(result).to be_success
      end
    end
  end

  context "when another plan has a wallet template with that code" do
    before { create(:plan_wallet, organization:, code: "ai_credits") }

    it "creates the wallet template" do
      expect(result).to be_success
    end
  end
end
