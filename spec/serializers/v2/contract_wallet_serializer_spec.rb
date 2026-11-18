# frozen_string_literal: true

require "rails_helper"

describe V2::ContractWalletSerializer do
  subject(:payload) { described_class.new(contract_wallet, options).serialize }

  let_it_be(:organization) { create(:organization) }
  let_it_be(:customer) { create(:customer, organization:, external_id: "acme") }
  let_it_be(:contract) { create(:contract, organization:, customer:, external_id: "acme-pro") }

  let(:contract_wallet) do
    create(:catalog_wallet, organization:, customer:, contract:, code: "ai_credits", name: "AI credits",
      invoice_display_name: "Prepaid credits", currency:, tax_application: "tax_on_purchase", priority: 10,
      top_up_min_amount_cents: 1000, top_up_max_amount_cents: 50_000, balance_cents: 43_000, terminated_at:, deleted_at:)
  end
  let(:currency) { "USD" }
  let(:terminated_at) { nil }
  let(:deleted_at) { nil }
  let(:options) { {} }
  let(:flat_payload) do
    {
      lago_id: contract_wallet.id,
      external_contract_id: "acme-pro",
      external_customer_id: "acme",
      code: "ai_credits",
      name: "AI credits",
      invoice_display_name: "Prepaid credits",
      currency: "USD",
      tax_application: "tax_on_purchase",
      priority: 10,
      applies_to: {include: []},
      top_up_min_amount_cents: 1000,
      top_up_max_amount_cents: 50_000,
      balance: "430.00",
      ongoing_balance: "430.00",
      terminated_at: nil,
      created_at: contract_wallet.created_at.iso8601,
      updated_at: contract_wallet.updated_at.iso8601,
      deleted_at: nil
    }
  end

  it "serializes the wallet, open to every fee, with its balances as decimal strings" do
    expect(payload).to eq(flat_payload)
  end

  context "when the currency has no minor unit" do
    let(:currency) { "JPY" }

    it "renders the balances without decimals" do
      expect(payload).to eq(flat_payload.merge(currency: "JPY", balance: "43000", ongoing_balance: "43000"))
    end
  end

  context "when the wallet is terminated" do
    let(:terminated_at) { Time.zone.parse("2026-10-01 10:00:00") }

    it "includes the termination timestamp" do
      expect(payload).to eq(flat_payload.merge(terminated_at: "2026-10-01T10:00:00Z"))
    end
  end

  context "when the wallet is deleted" do
    let(:deleted_at) { Time.zone.parse("2026-10-01 10:00:00") }

    it "includes the deletion timestamp" do
      expect(payload).to eq(flat_payload.merge(deleted_at: "2026-10-01T10:00:00Z"))
    end
  end

  context "with selectors" do
    let(:product_category) { create(:product_category, organization:, code: "ai") }
    let(:product) { create(:product, organization:, code: "api_calls") }
    let(:product_filter) { create(:product_filter, organization:, product:, code: "premium_model") }

    before do
      [
        {selector_type: "fee_type", fee_type: "metered"},
        {selector_type: "product_category", fee_type: nil, product_category:},
        {selector_type: "product", fee_type: nil, product:, with_product_filters: true},
        {selector_type: "product_filters", fee_type: nil, product_filter:}
      ].each_with_index do |target, index|
        create(:catalog_wallet_selector, organization:, catalog_wallet: contract_wallet, created_at: index.minutes.from_now, **target)
      end
    end

    it "renders each one as a request names it, in the order they were added" do
      expect(payload).to eq(flat_payload.merge(applies_to: {include: [
        {type: "fee_type", code: "metered"},
        {type: "product_category", code: "ai"},
        {type: "product", code: "api_calls", with_product_filters: true},
        {type: "product_filters", product_code: "api_calls", code: "premium_model"}
      ]}))
    end
  end

  context "with the taxes expansion" do
    let(:options) { {includes: %i[taxes]} }
    let(:vat) { create(:tax, organization:) }
    let(:gst) { create(:tax, organization:) }

    before do
      create(:catalog_wallet_applied_tax, organization:, catalog_wallet: contract_wallet, tax: gst, created_at: 2.days.ago)
      create(:catalog_wallet_applied_tax, organization:, catalog_wallet: contract_wallet, tax: vat, created_at: 1.day.ago)
      create(:catalog_wallet_applied_tax, organization:, catalog_wallet: contract_wallet, tax: create(:tax, organization:, deleted_at: Time.current))
    end

    it "embeds the kept taxes, the latest linked first" do
      expect(payload).to eq(flat_payload.merge(taxes: [vat, gst].map { V2::TaxSerializer.new(it).serialize }))
    end
  end

  context "with the metadata expansion" do
    let(:options) { {includes: %i[metadata]} }

    it "embeds a null when the wallet has none" do
      expect(payload).to eq(flat_payload.merge(metadata: nil))
    end

    context "when the wallet has metadata" do
      before { create(:item_metadata, organization:, owner: contract_wallet, value: {"team" => "growth"}) }

      it "embeds its content" do
        expect(payload).to eq(flat_payload.merge(metadata: {"team" => "growth"}))
      end
    end
  end
end
