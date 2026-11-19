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
      expect(json[:plan_wallets].map { it[:lago_id] }).to eq([plan_wallet.id])
      expect(json[:plan_wallets].sole.keys).to eq(flat_keys)
      expect(json[:meta]).to eq(next_cursor: nil, prev_cursor: nil)
    end

    context "when another organization has a plan with the same code" do
      let(:other_plan) { create(:catalog_plan, organization: create(:organization), code: "pro") }

      before { create(:plan_wallet, organization: other_plan.organization, catalog_plan: other_plan, code: "foreign") }

      it "leaves its wallet templates out" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:plan_wallets].map { it[:code] }).to eq(["ai_credits"])
      end
    end

    context "when wallet templates have selectors", :bullet do
      let(:other_plan_wallet) { create(:plan_wallet, organization:, catalog_plan:, code: "support_credits", currency: "USD", priority: 20) }

      before do
        product = create(:product, organization:)

        [plan_wallet, other_plan_wallet].each do |wallet|
          create(:catalog_wallet_selector, :plan_level, organization:, plan_wallet: wallet)
          create(:catalog_wallet_selector, :plan_level, organization:, plan_wallet: wallet, selector_type: "product", fee_type: nil, product:)
          create(:catalog_wallet_selector, :plan_level, organization:, plan_wallet: wallet, selector_type: "product_category", fee_type: nil,
            product_category: product.product_category)
          create(:catalog_wallet_selector, :plan_level, organization:, plan_wallet: wallet, selector_type: "product_filters", fee_type: nil,
            product_filter: create(:product_filter, organization:, product:))
        end
      end

      it "renders their scopes without a query per wallet template or selector" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:plan_wallets].map { it[:applies_to][:include].map { |entry| entry[:type] }.sort })
          .to eq([%w[fee_type product product_category product_filters]] * 2)
      end
    end

    context "when the plan does not exist" do
      let(:plan_code) { "unknown" }

      it "returns a not found error" do
        subject

        expect(response).to be_v2_not_found_error("plan")
      end
    end

    it_behaves_like "a cursor paginated v2 endpoint", collection: :plan_wallets, model: PlanWallet do
      let(:paginated_path) { "/api/v2/plans/#{catalog_plan.code}/wallets" }
      let(:create_paginated_record) { ->(created_at) { create(:plan_wallet, organization:, catalog_plan:, created_at:) } }
    end

    it_behaves_like "a v2 list filtered on created_at", collection: :plan_wallets do
      let(:filtered_path) { "/api/v2/plans/#{catalog_plan.code}/wallets" }
      let(:create_filtered_record) { ->(created_at) { create(:plan_wallet, organization:, catalog_plan:, created_at:) } }
    end
  end

  describe "GET /api/v2/plans/:plan_code/wallets/:code" do
    subject { get_with_token(organization, "/api/v2/plans/#{plan_code}/wallets/#{code}", query) }

    let(:plan_code) { catalog_plan.code }
    let(:code) { plan_wallet.code }
    let(:query) { {} }

    include_examples "requires API permission", "plan_wallet", "read"
    include_examples "requires the catalog_wallets flag"

    it "returns the wallet template" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:plan_wallet]).to include(
        lago_id: plan_wallet.id, plan_code: "pro", code: "ai_credits", currency: "USD",
        tax_application: "tax_on_consumption", priority: 10, applies_to: {include: []}, deleted_at: nil
      )
      expect(json[:plan_wallet].keys).to eq(flat_keys)
    end

    context "when the wallet template has selectors", :bullet do
      before do
        product = create(:product, organization:, code: "api_calls")
        create(:catalog_wallet_selector, :plan_level, organization:, plan_wallet:, selector_type: "product", fee_type: nil, product:)
        create(:catalog_wallet_selector, :plan_level, organization:, plan_wallet:, selector_type: "product", fee_type: nil,
          product: create(:product, organization:, code: "storage"))
        create(:catalog_wallet_selector, :plan_level, organization:, plan_wallet:, selector_type: "product_category", fee_type: nil,
          product_category: product.product_category)
        create(:catalog_wallet_selector, :plan_level, organization:, plan_wallet:, selector_type: "product_filters", fee_type: nil,
          product_filter: create(:product_filter, organization:, product:))
      end

      it "renders its scope without a query per selector" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:plan_wallet][:applies_to][:include].map { it[:type] }).to match_array(%w[product product product_category product_filters])
      end
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
        expect(json[:plan_wallet].keys).to eq(flat_keys + %i[taxes metadata])
        expect(json[:plan_wallet][:taxes].map { it[:code] }).to eq(["vat_20"])
        expect(json[:plan_wallet][:metadata]).to eq(team: "growth")
      end
    end

    context "when it does not exist" do
      let(:code) { "unknown" }

      it "returns a not found error" do
        subject

        expect(response).to be_v2_not_found_error("plan_wallet")
      end
    end

    context "when it belongs to another plan" do
      let(:code) { create(:plan_wallet, organization:, code: "other").code }

      it "returns a not found error" do
        subject

        expect(response).to be_v2_not_found_error("plan_wallet")
      end
    end

    context "when it is deleted" do
      let(:code) { create(:plan_wallet, organization:, catalog_plan:, code: "old", deleted_at: Time.current).code }

      it "returns a not found error" do
        subject

        expect(response).to be_v2_not_found_error("plan_wallet")
      end
    end

    context "when the plan does not exist" do
      let(:plan_code) { "unknown" }

      it "returns a not found error on the wallet template" do
        subject

        expect(response).to be_v2_not_found_error("plan_wallet")
      end
    end

    context "when it belongs to a plan of another organization with the same code" do
      let(:other_plan) { create(:catalog_plan, organization: create(:organization), code: "pro") }
      let(:code) { create(:plan_wallet, organization: other_plan.organization, catalog_plan: other_plan, code: "foreign").code }

      before { catalog_plan }

      it "returns a not found error" do
        subject

        expect(response).to be_v2_not_found_error("plan_wallet")
      end
    end
  end
end
