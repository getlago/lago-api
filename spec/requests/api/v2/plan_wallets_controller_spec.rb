# frozen_string_literal: true

require "rails_helper"

describe Api::V2::PlanWalletsController do
  let(:organization) { create(:organization, feature_flags:) }
  let(:feature_flags) { %w[product_catalog catalog_wallets] }
  let(:catalog_plan) { create(:catalog_plan, organization:, code: "pro", currency: "USD") }
  let(:plan_wallet) { create(:plan_wallet, organization:, catalog_plan:, code: "ai_credits", currency: "USD", priority: 10) }
  let(:flat_keys) do
    %i[
      lago_id plan_code code name invoice_display_name currency tax_application priority applies_to
      top_up_min_amount_cents top_up_max_amount_cents created_at updated_at deleted_at
    ]
  end

  shared_examples "requires the catalog_wallets flag" do
    context "when the organization is not on catalog wallets" do
      let(:feature_flags) { %w[product_catalog] }

      it "returns a forbidden error" do
        subject

        expect(response).to have_http_status(:forbidden)
        expect(json).to eq(code: "feature_unavailable", details: [])
      end
    end
  end

  describe "GET /api/v2/plans/:plan_code/wallets" do
    subject { get_with_token(organization, "/api/v2/plans/#{plan_code}/wallets") }

    let(:plan_code) { catalog_plan.code }

    before do
      plan_wallet
      create(:plan_wallet, organization:)
      create(:plan_wallet, organization:, catalog_plan:, deleted_at: Time.current)
    end

    include_examples "requires API permission", "plan_wallet", "read"
    include_examples "requires the catalog_wallets flag"

    it "returns the plan's kept wallet templates only" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:wallets].map { it[:lago_id] }).to eq([plan_wallet.id])
      expect(json[:wallets].sole.keys).to eq(flat_keys)
      expect(json[:meta]).to eq(next_cursor: nil, prev_cursor: nil)
    end

    context "when a wallet template has selectors", :bullet do
      before do
        product = create(:product, organization:)
        create(:catalog_wallet_selector, :plan_level, organization:, plan_wallet:)
        create(:catalog_wallet_selector, :plan_level, organization:, plan_wallet:, selector_type: "product", fee_type: nil, product:)
        create(:catalog_wallet_selector, :plan_level, organization:, plan_wallet:, selector_type: "product_category", fee_type: nil,
          product_category: product.product_category)
        create(:catalog_wallet_selector, :plan_level, organization:, plan_wallet:, selector_type: "product_filters", fee_type: nil,
          product_filter: create(:product_filter, organization:, product:))
      end

      it "renders its scope without a query per selector" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:wallets].sole[:applies_to][:include].map { it[:type] }).to match_array(%w[fee_type product product_category product_filters])
      end
    end

    context "when the plan does not exist" do
      let(:plan_code) { "unknown" }

      it "returns a not found error" do
        subject

        expect(response).to be_v2_not_found_error("plan")
      end
    end

    it_behaves_like "a cursor paginated v2 endpoint", collection: :wallets, model: PlanWallet do
      let(:paginated_path) { "/api/v2/plans/#{catalog_plan.code}/wallets" }
      let(:create_paginated_record) { ->(created_at) { create(:plan_wallet, organization:, catalog_plan:, created_at:) } }
    end

    it_behaves_like "a v2 list filtered on created_at", collection: :wallets do
      let(:filtered_path) { "/api/v2/plans/#{catalog_plan.code}/wallets" }
      let(:create_filtered_record) { ->(created_at) { create(:plan_wallet, organization:, catalog_plan:, created_at:) } }
    end
  end

  describe "GET /api/v2/plans/:plan_code/wallets/:code" do
    subject { get_with_token(organization, "/api/v2/plans/#{catalog_plan.code}/wallets/#{code}", query) }

    let(:code) { plan_wallet.code }
    let(:query) { {} }

    include_examples "requires API permission", "plan_wallet", "read"
    include_examples "requires the catalog_wallets flag"

    it "returns the wallet template" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:wallet]).to include(
        lago_id: plan_wallet.id, plan_code: "pro", code: "ai_credits", currency: "USD",
        tax_application: "tax_on_consumption", priority: 10, applies_to: {include: []}, deleted_at: nil
      )
      expect(json[:wallet].keys).to eq(flat_keys)
    end

    context "with the taxes and metadata expansions" do
      let(:query) { {expands: %w[taxes metadata]} }
      let(:tax) { create(:tax, organization:, code: "vat_20") }

      before do
        create(:catalog_wallet_applied_tax, :plan_level, organization:, plan_wallet:, tax:)
        create(:item_metadata, organization:, owner: plan_wallet, value: {"team" => "growth"})
      end

      it "embeds them" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:wallet].keys).to eq(flat_keys + %i[taxes metadata])
        expect(json[:wallet][:taxes].map { it[:code] }).to eq(["vat_20"])
        expect(json[:wallet][:metadata]).to eq(team: "growth")
      end
    end

    context "when it does not exist" do
      let(:code) { "unknown" }

      it "returns a not found error" do
        subject

        expect(response).to be_v2_not_found_error("wallet")
      end
    end

    context "when it belongs to another plan" do
      let(:code) { create(:plan_wallet, organization:, code: "other").code }

      it "returns a not found error" do
        subject

        expect(response).to be_v2_not_found_error("wallet")
      end
    end
  end
end
