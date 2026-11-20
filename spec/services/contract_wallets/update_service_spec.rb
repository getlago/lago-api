# frozen_string_literal: true

require "rails_helper"

describe ContractWallets::UpdateService do
  subject(:result) { described_class.call(contract_wallet:, params:) }

  let_it_be(:organization) { create(:organization) }
  let_it_be(:customer) { create(:customer, organization:, currency: "USD") }
  let_it_be(:tax) { create(:tax, organization:, code: "vat_20") }
  let_it_be(:product) { create(:product, organization:, code: "api_calls") }

  let(:contract) { create(:contract, organization:, customer:) }
  let(:contract_wallet) do
    create(:catalog_wallet, organization:, customer:, contract:, code: "ai_credits", currency: "USD", priority: 10,
      top_up_min_amount_cents: 1000, balance_cents: 43_000, updated_at: 1.day.ago)
  end
  let(:params) do
    {name: "Credits", invoice_display_name: "Prepaid credits", priority: 20, top_up_min_amount_cents: nil, top_up_max_amount_cents: 50_000}
  end

  before { allow(Utils::ActivityLog).to receive(:produce).and_call_original }

  it "updates the wallet's own fields" do
    expect(result).to be_success
    expect(result.contract_wallet.reload).to have_attributes(
      code: "ai_credits",
      name: "Credits",
      invoice_display_name: "Prepaid credits",
      currency: "USD",
      tax_application: "tax_on_consumption",
      priority: 20,
      top_up_min_amount_cents: nil,
      top_up_max_amount_cents: 50_000,
      balance_cents: 43_000
    )
  end

  it "logs the update" do
    result

    expect(Utils::ActivityLog).to have_received(:produce).with(contract_wallet, "contract_wallet.updated", after_commit: true)
  end

  context "when the contract is pending" do
    let(:contract) { create(:contract, :pending, organization:, customer:) }

    it "updates the wallet" do
      expect(result).to be_success
      expect(contract_wallet.reload.priority).to eq(20)
    end
  end

  [:terminated, :canceled].each do |status|
    context "when the contract is #{status}" do
      let(:contract) { create(:contract, status, organization:, customer:) }

      it "refuses it and changes nothing" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ForbiddenFailure)
        expect(result.error.code).to eq("contract_not_live")
        expect(contract_wallet.reload.priority).to eq(10)
      end
    end
  end

  context "when the contract has ended since the wallet was loaded" do
    before do
      contract_wallet
      Contract.find(contract.id).update!(status: :terminated, terminated_at: Time.current)
    end

    it "refuses it and changes nothing" do
      expect(result).not_to be_success
      expect(result.error.code).to eq("contract_not_live")
      expect(contract_wallet.reload.priority).to eq(10)
    end
  end

  context "when the wallet does not exist" do
    let(:contract_wallet) { nil }

    it "returns a contract wallet not found failure" do
      expect(result).not_to be_success
      expect(result.error.resource).to eq("contract_wallet")
    end
  end

  context "when another request has deleted the wallet" do
    subject(:result) { described_class.call(contract_wallet: stale_contract_wallet, params:) }

    let(:stale_contract_wallet) { CatalogWallet.find(contract_wallet.id) }

    before do
      stale_contract_wallet
      contract_wallet.discard!
    end

    it "returns a contract wallet not found failure and changes nothing" do
      expect(result).not_to be_success
      expect(result.error.resource).to eq("contract_wallet")
      expect(contract_wallet.reload.priority).to eq(10)
    end
  end

  context "when the wallet has paid invoices" do
    let(:inbound) { create(:catalog_wallet_transaction, organization:, catalog_wallet: contract_wallet, remaining_credit_amount_cents: 7_000) }
    let(:consumption) { create(:catalog_wallet_consumption, organization:, inbound_transaction: inbound, credit_amount_cents: 3_000) }
    let(:params) { {priority: 20, applies_to: {include: [{type: "product", code: "api_calls"}]}} }

    before do
      create(:catalog_wallet_selector, organization:, catalog_wallet: contract_wallet)
      consumption
    end

    it "changes the scope and the priority without touching what was already spent" do
      expect { result }.not_to change { [inbound.reload.attributes, consumption.reload.attributes, consumption.outbound_transaction.reload.attributes] }

      expect(result).to be_success
      expect(contract_wallet.reload.priority).to eq(20)
      expect(contract_wallet.selectors.map { [it.selector_type, it.product_id] }).to eq([["product", product.id]])
    end
  end

  context "with taxes, a scope and metadata" do
    let(:params) do
      {tax_codes: ["vat_20"], applies_to: {include: [{type: "product", code: "api_calls"}]}, metadata: {team: "growth"}}
    end

    before do
      create(:catalog_wallet_applied_tax, organization:, catalog_wallet: contract_wallet)
      create(:catalog_wallet_selector, organization:, catalog_wallet: contract_wallet)
      create(:item_metadata, organization:, owner: contract_wallet, value: {"team" => "sales", "tier" => "gold"})
    end

    it "replaces each of them and dates the edit" do
      freeze_time do
        expect(result).to be_success
        expect(contract_wallet.reload.taxes).to eq([tax])
        expect(contract_wallet.selectors.map { [it.selector_type, it.product_id] }).to eq([["product", product.id]])
        expect(contract_wallet.metadata.value).to eq({"team" => "growth"})
        expect(contract_wallet.updated_at).to eq(Time.current)
      end
    end

    {
      tax_codes: ["vat_20"],
      applies_to: {include: [{type: "product", code: "api_calls"}]},
      metadata: {team: "growth"}
    }.each do |key, value|
      context "when only #{key} is sent" do
        let(:params) { {key => value} }

        it "dates the edit" do
          freeze_time do
            expect(result).to be_success
            expect(contract_wallet.reload.updated_at).to eq(Time.current)
          end
        end
      end
    end

    context "when they are emptied" do
      let(:params) { {tax_codes: [], applies_to: {include: []}, metadata: nil} }

      it "removes them" do
        expect(result).to be_success
        expect(contract_wallet.reload.taxes).to be_empty
        expect(contract_wallet.selectors).to be_empty
        expect(contract_wallet.metadata).to be_nil
      end
    end

    context "when they are not sent" do
      let(:params) { {priority: 20} }

      it "leaves them as they were" do
        expect(result).to be_success
        expect(contract_wallet.reload.taxes.count).to eq(1)
        expect(contract_wallet.selectors.map(&:selector_type)).to eq(["fee_type"])
        expect(contract_wallet.metadata.value).to eq({"team" => "sales", "tier" => "gold"})
      end
    end

    context "when a selector is refused" do
      let(:params) { {priority: 20, tax_codes: [], applies_to: {include: [{type: "product", code: "unknown"}]}} }

      it "fails on that entry and changes nothing" do
        expect(result).not_to be_success
        expect(result.error.messages).to eq({"applies_to.include[0].code": ["product_not_found"]})
        expect(contract_wallet.reload).to have_attributes(priority: 10, updated_at: be < 1.hour.ago)
        expect(contract_wallet.taxes.count).to eq(1)
      end
    end
  end

  describe "immutable fields" do
    [
      ["another currency", {currency: "EUR"}, :currency],
      ["a null currency", {currency: nil}, :currency],
      ["another tax application", {tax_application: "tax_on_purchase"}, :tax_application],
      ["an unknown tax application", {tax_application: "tax_free"}, :tax_application],
      ["another code", {code: "credits"}, :code]
    ].each do |description, overrides, field|
      context "with #{description}" do
        let(:params) { {priority: 20}.merge(overrides) }

        it "fails on that field and changes nothing" do
          expect(result).not_to be_success
          expect(result.error.messages).to eq({field => ["not_editable"]})
          expect(contract_wallet.reload).to have_attributes(code: "ai_credits", currency: "USD", tax_application: "tax_on_consumption", priority: 10)
        end
      end
    end

    context "when they are sent unchanged" do
      let(:params) { {code: "ai_credits", currency: "USD", tax_application: "tax_on_consumption", priority: 20} }

      it "updates the other fields" do
        expect(result).to be_success
        expect(contract_wallet.reload).to have_attributes(code: "ai_credits", currency: "USD", tax_application: "tax_on_consumption", priority: 20)
      end
    end
  end

  describe "refused params" do
    [
      ["a null priority", {priority: nil}, {priority: ["value_is_invalid"]}],
      ["a priority above 50", {priority: 51}, {priority: ["value_is_out_of_range"]}, {priority: {max: 50}}],
      ["metadata that is not an object", {metadata: "growth"}, {metadata: ["value_is_invalid"]}],
      ["a metadata value that is not a string", {metadata: {seats: 5}}, {metadata: ["value_is_invalid"]}],
      ["tax codes that are not a list", {tax_codes: "vat_20"}, {tax_codes: ["value_is_invalid"]}],
      ["a top-up maximum below the minimum", {top_up_min_amount_cents: 1000, top_up_max_amount_cents: 999}, {top_up_max_amount_cents: ["value_is_out_of_range"]}, {top_up_max_amount_cents: {min: 1000}}],
      ["an excluded scope", {applies_to: {exclude: []}}, {"applies_to.exclude": ["not_supported"]}]
    ].each do |description, overrides, messages, meta|
      context "with #{description}" do
        let(:params) { {name: "Credits"}.merge(overrides) }

        it "fails on that field and changes nothing" do
          expect(result).not_to be_success
          expect(result.error.messages).to eq(messages)
          expect(result.error.meta).to eq(meta || {})
          expect(contract_wallet.reload).to have_attributes(name: "Prepaid credits", priority: 10)
        end
      end
    end

    context "with a tax that does not exist" do
      let(:params) { {priority: 20, tax_codes: ["unknown"]} }

      it "returns a tax not found failure and changes nothing" do
        expect(result).not_to be_success
        expect(result.error.resource).to eq("tax")
        expect(contract_wallet.reload.priority).to eq(10)
      end
    end
  end
end
