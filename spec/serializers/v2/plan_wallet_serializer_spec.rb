# frozen_string_literal: true

require "rails_helper"

describe V2::PlanWalletSerializer do
  subject(:payload) { described_class.new(plan_wallet, options).serialize }

  let_it_be(:organization) { create(:organization) }
  let_it_be(:catalog_plan) { create(:catalog_plan, organization:, code: "pro") }

  let(:plan_wallet) do
    create(:plan_wallet, organization:, catalog_plan:, code: "ai_credits", name: "AI credits",
      invoice_display_name: "Prepaid credits", currency: "USD", tax_application: "tax_on_purchase",
      priority: 10, top_up_min_amount_cents: 1000, top_up_max_amount_cents: 50_000, deleted_at:)
  end
  let(:deleted_at) { nil }
  let(:options) { {} }
  let(:flat_payload) do
    {
      lago_id: plan_wallet.id,
      plan_code: "pro",
      code: "ai_credits",
      name: "AI credits",
      invoice_display_name: "Prepaid credits",
      currency: "USD",
      tax_application: "tax_on_purchase",
      priority: 10,
      applies_to: {include: []},
      top_up_min_amount_cents: 1000,
      top_up_max_amount_cents: 50_000,
      created_at: plan_wallet.created_at.iso8601,
      updated_at: plan_wallet.updated_at.iso8601,
      deleted_at: nil
    }
  end

  it "serializes the wallet template, open to every fee" do
    expect(payload).to eq(flat_payload)
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
        create(:catalog_wallet_selector, :plan_level, organization:, plan_wallet:, created_at: index.minutes.from_now, **target)
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

    context "when several selectors name a product" do
      before do
        create(:catalog_wallet_selector, :plan_level, organization:, plan_wallet:, selector_type: "product", fee_type: nil,
          product: create(:product, organization:, code: "storage"))
      end

      it "loads the products in one query" do
        product_queries = 0
        counter = lambda do |_name, _start, _finish, _id, payload|
          product_queries += 1 if payload[:sql].include?('FROM "products"')
        end

        ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { payload }

        expect(payload[:applies_to][:include].count { it[:type] == "product" }).to eq(2)
        expect(product_queries).to eq(1)
      end
    end
  end

  context "with the taxes expansion" do
    let(:options) { {includes: %i[taxes]} }
    let(:vat) { create(:tax, organization:) }
    let(:gst) { create(:tax, organization:) }

    before do
      create(:catalog_wallet_applied_tax, :plan_level, organization:, plan_wallet:, tax: gst, created_at: 2.days.ago)
      create(:catalog_wallet_applied_tax, :plan_level, organization:, plan_wallet:, tax: vat, created_at: 1.day.ago)
      create(:catalog_wallet_applied_tax, :plan_level, organization:, plan_wallet:, tax: create(:tax, organization:, deleted_at: Time.current))
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
      before { create(:item_metadata, organization:, owner: plan_wallet, value: {"team" => "growth"}) }

      it "embeds its content" do
        expect(payload).to eq(flat_payload.merge(metadata: {"team" => "growth"}))
      end
    end
  end
end
