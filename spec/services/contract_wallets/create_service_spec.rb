# frozen_string_literal: true

require "rails_helper"

describe ContractWallets::CreateService do
  subject(:result) { described_class.call(contract:, params:) }

  let_it_be(:organization) { create(:organization) }
  let_it_be(:customer) { create(:customer, organization:, currency: "USD") }
  let_it_be(:tax) { create(:tax, organization:, code: "vat_20") }
  let_it_be(:product) { create(:product, organization:, code: "api_calls") }

  let(:contract) { create(:contract, organization:, customer:) }
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

  it "creates an empty wallet on the contract with its taxes, scope and metadata" do
    expect { result }.to change(contract.wallets, :count).by(1)

    expect(result).to be_success
    expect(result.contract_wallet).to have_attributes(
      organization_id: organization.id,
      contract_id: contract.id,
      customer_id: customer.id,
      code: "ai_credits",
      name: "AI credits",
      invoice_display_name: "Prepaid credits",
      currency: "USD",
      tax_application: "tax_on_purchase",
      priority: 10,
      top_up_min_amount_cents: 1000,
      top_up_max_amount_cents: 50_000,
      balance_cents: 0
    )
    expect(result.contract_wallet.taxes).to eq([tax])
    expect(result.contract_wallet.selectors.map { [it.selector_type, it.fee_type, it.product_id] })
      .to match_array([["fee_type", "metered", nil], ["product", nil, product.id]])
    expect(result.contract_wallet.metadata.value).to eq({"team" => "growth"})
  end

  it "logs the creation" do
    result

    expect(Utils::ActivityLog).to have_received(:produce).with(result.contract_wallet, "contract_wallet.created", after_commit: true)
  end

  it "locks the contract without holding back the rows that reference it" do
    statements = capture_sql { result }

    expect(statements).to include(a_string_matching(/FROM "contracts".*FOR NO KEY UPDATE/))
  end

  context "with only the required fields" do
    let(:params) { {code: "ai_credits", currency: "USD"} }

    it "creates an untaxed wallet open to every fee, with the defaults" do
      expect(result).to be_success
      expect(result.contract_wallet).to have_attributes(
        name: nil, tax_application: "tax_on_consumption", priority: 50, top_up_min_amount_cents: nil, top_up_max_amount_cents: nil
      )
      expect(result.contract_wallet.taxes).to be_empty
      expect(result.contract_wallet.selectors).to be_empty
      expect(result.contract_wallet.metadata).to be_nil
    end
  end

  context "when the contract is pending" do
    let(:contract) { create(:contract, :pending, organization:, customer:) }

    it "creates the wallet" do
      expect(result).to be_success
    end
  end

  context "when the contract has a plan" do
    let(:catalog_plan) { create(:catalog_plan, organization:, currency: "USD") }
    let(:contract) { create(:contract, organization:, customer:, catalog_plan:) }

    it "creates the wallet without changing the plan" do
      expect { result }.not_to change(catalog_plan.wallets, :count)

      expect(result).to be_success
    end
  end

  context "when the contract does not exist" do
    let(:contract) { nil }

    it "returns a contract not found failure" do
      expect(result).not_to be_success
      expect(result.error.resource).to eq("contract")
    end
  end

  [:terminated, :canceled].each do |status|
    context "when the contract is #{status}" do
      let(:contract) { create(:contract, status, organization:, customer:) }

      it "refuses it and writes nothing" do
        expect { result }.not_to change(CatalogWallet, :count)

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ForbiddenFailure)
        expect(result.error.code).to eq("contract_not_live")
      end
    end
  end

  context "when the contract has ended since it was loaded" do
    before do
      contract
      Contract.find(contract.id).update!(status: :terminated, terminated_at: Time.current)
    end

    it "refuses it and writes nothing" do
      expect { result }.not_to change(CatalogWallet, :count)

      expect(result).not_to be_success
      expect(result.error.code).to eq("contract_not_live")
    end
  end

  describe "refused params" do
    [
      ["a currency other than the contract's", {currency: "EUR"}, {currency: ["currency_does_not_match"]}],
      ["no currency", {currency: nil}, {currency: ["value_is_invalid"]}],
      ["no code", {code: nil}, {code: ["value_is_mandatory"]}],
      ["a code that is not URL safe", {code: "ai credits"}, {code: ["value_is_invalid"]}],
      ["metadata that is not an object", {metadata: "growth"}, {metadata: ["value_is_invalid"]}],
      ["a metadata value that is not a string", {metadata: {seats: 5}}, {metadata: ["value_is_invalid"]}],
      ["tax codes that are not a list", {tax_codes: "vat_20"}, {tax_codes: ["value_is_invalid"]}],
      ["an unknown tax application", {tax_application: "tax_free"}, {tax_application: ["value_is_invalid"]}, {tax_application: {allowed_values: %w[tax_on_consumption tax_on_purchase]}}],
      ["a priority above 50", {priority: 51}, {priority: ["value_is_out_of_range"]}, {priority: {max: 50}}],
      ["a priority that is not a number", {priority: "high"}, {priority: ["value_is_invalid"]}],
      ["a fractional top-up maximum", {top_up_max_amount_cents: 60_000.5}, {top_up_max_amount_cents: ["value_is_invalid"]}],
      ["a top-up minimum above the maximum", {top_up_min_amount_cents: 50_001}, {top_up_max_amount_cents: ["value_is_out_of_range"]}, {top_up_max_amount_cents: {min: 50_001}}],
      ["an excluded scope", {applies_to: {exclude: [{type: "fee_type", code: "fixed"}]}}, {"applies_to.exclude": ["not_supported"]}],
      ["a selector that does not exist", {applies_to: {include: [{type: "product", code: "unknown"}]}}, {"applies_to.include[0].code": ["product_not_found"]}]
    ].each do |description, overrides, messages, meta|
      context "with #{description}" do
        let(:params) { super().merge(overrides) }

        it "fails on that field and writes nothing" do
          expect { result }.not_to change { [CatalogWallet.count, CatalogWalletAppliedTax.count, CatalogWalletSelector.count, Metadata::ItemMetadata.count] }

          expect(result).not_to be_success
          expect(result.error.messages).to eq(messages)
          expect(result.error.meta).to eq(meta || {})
        end
      end
    end

    context "with a tax that does not exist" do
      let(:params) { super().merge(tax_codes: %w[vat_20 unknown]) }

      it "returns a tax not found failure and writes nothing" do
        expect { result }.not_to change { [CatalogWallet.count, CatalogWalletAppliedTax.count] }

        expect(result).not_to be_success
        expect(result.error.resource).to eq("tax")
      end
    end
  end

  context "when the contract already has a wallet with that code" do
    before { create(:catalog_wallet, organization:, customer:, contract:, code: "ai_credits") }

    it "fails on the code" do
      expect(result).not_to be_success
      expect(result.error.messages).to eq({code: ["value_already_exist"]})
    end

    context "when that wallet is deleted" do
      before { contract.wallets.find_by(code: "ai_credits").discard! }

      it "creates the wallet" do
        expect(result).to be_success
      end
    end

    context "when a concurrent request wrote it after the uniqueness check" do
      let(:uniqueness_check) { CatalogWallet.validators_on(:code).grep(ActiveRecord::Validations::UniquenessValidator).sole }

      before { allow(uniqueness_check).to receive(:validate_each) }

      it "fails on the code and writes nothing" do
        expect { result }.not_to change(CatalogWallet, :count)

        expect(result).not_to be_success
        expect(result.error.messages).to eq({code: ["value_already_exist"]})
      end
    end
  end

  context "when another contract has a wallet with that code" do
    before { create(:catalog_wallet, organization:, code: "ai_credits") }

    it "creates the wallet" do
      expect(result).to be_success
    end
  end
end
