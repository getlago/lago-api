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

  describe "POST /api/v2/plans/:plan_code/wallets" do
    subject { post_with_token(organization, "/api/v2/plans/#{plan_code}/wallets", {wallet: create_params}) }

    let(:plan_code) { catalog_plan.code }
    let(:product) { create(:product, organization:, code: "api_calls") }
    let(:create_params) do
      {
        code: "ai_credits",
        name: "AI credits",
        invoice_display_name: "Prepaid credits",
        currency: "USD",
        tax_application: "tax_on_purchase",
        tax_codes: ["vat_20"],
        applies_to: {include: selectors},
        priority: 10,
        top_up_min_amount_cents: 1000,
        top_up_max_amount_cents: 50_000,
        metadata: {team: "growth"}
      }
    end
    let(:selectors) do
      [
        {type: "fee_type", code: "metered"},
        {type: "product_category", code: "ai"},
        {type: "product", code: "api_calls", with_product_filters: true},
        {type: "product_filters", product_code: "api_calls", code: "premium_model"}
      ]
    end

    before do
      create(:tax, organization:, code: "vat_20")
      create(:product_category, organization:, code: "ai")
      create(:product_filter, organization:, product:, code: "premium_model")
    end

    include_examples "requires API permission", "plan_wallet", "write"
    include_examples "requires the catalog_wallets flag"

    it "adds the wallet template to the plan" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:wallet]).to include(
        plan_code: "pro",
        code: "ai_credits",
        name: "AI credits",
        invoice_display_name: "Prepaid credits",
        currency: "USD",
        tax_application: "tax_on_purchase",
        priority: 10,
        applies_to: {include: selectors},
        top_up_min_amount_cents: 1000,
        top_up_max_amount_cents: 50_000,
        deleted_at: nil
      )
      expect(json[:wallet].keys).to eq(flat_keys)
      expect(catalog_plan.wallets.sole).to have_attributes(id: json[:wallet][:lago_id], taxes: [Tax.find_by(code: "vat_20")])
      expect(catalog_plan.wallets.sole.metadata.value).to eq({"team" => "growth"})
    end

    context "when a product selector leaves the filters flag out or off" do
      let(:selectors) { [{type: "product", code: "api_calls"}, {type: "product", code: product2.code, with_product_filters: false}] }
      let(:product2) { create(:product, organization:) }

      it "selects the products without their filters" do
        subject

        expect(json[:wallet][:applies_to][:include]).to eq([
          {type: "product", code: "api_calls", with_product_filters: false},
          {type: "product", code: product2.code, with_product_filters: false}
        ])
      end
    end

    context "when include is empty" do
      let(:selectors) { [] }

      it "leaves the wallet template open to every fee" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:wallet][:applies_to]).to eq(include: [])
      end
    end

    context "when the plan does not exist" do
      let(:plan_code) { "unknown" }

      it "returns a not found error" do
        subject

        expect(response).to be_v2_not_found_error("plan")
      end
    end

    context "when a tax does not exist" do
      let(:create_params) { super().merge(tax_codes: ["unknown"]) }

      it "returns a not found error and adds nothing" do
        expect { subject }.not_to change(PlanWallet, :count)

        expect(response).to be_v2_not_found_error("tax")
      end
    end

    describe "validations" do
      [
        ["a priority below 1", {priority: 0}, "value_is_invalid", "priority"],
        ["a priority above 50", {priority: 51}, "value_is_invalid", "priority"],
        ["a rate amount", {rate_amount: "1.0"}, "not_supported", "rate_amount"],
        ["a currency other than the plan's", {currency: "EUR"}, "currency_does_not_match", "currency"],
        ["an unknown tax application", {tax_application: "tax_free"}, "value_is_invalid", "tax_application"],
        ["a negative top-up minimum", {top_up_min_amount_cents: -1}, "value_is_out_of_range", "top_up_min_amount_cents"],
        ["a fractional top-up maximum", {top_up_max_amount_cents: 60_000.5}, "value_is_invalid", "top_up_max_amount_cents"],
        ["a top-up minimum above the maximum", {top_up_min_amount_cents: 50_001}, "value_is_out_of_range", "top_up_max_amount_cents"],
        ["an excluded scope", {applies_to: {exclude: [{type: "fee_type", code: "fixed"}]}}, "not_supported", "applies_to.exclude"],
        ["a selector that does not exist", {applies_to: {include: [{type: "fee_type", code: "metered"}, {type: "product", code: "unknown"}]}}, "product_not_found", "applies_to.include[1].code"]
      ].each do |description, overrides, code, field|
        context "with #{description}" do
          let(:create_params) { super().merge(overrides) }

          it "returns a validation error on #{field} and adds nothing" do
            expect { subject }.not_to change { [PlanWallet.count, CatalogWalletSelector.count, CatalogWalletAppliedTax.count] }

            expect(response).to have_http_status(:unprocessable_content)
            expect(json[:code]).to eq("validation_errors")
            expect(json[:details].map { it.slice(:code, :field) }).to eq([{code:, field:}])
          end
        end
      end

      context "with a code the plan already uses" do
        before { plan_wallet }

        it "returns a validation error on code" do
          subject

          expect(response).to have_http_status(:unprocessable_content)
          expect(json[:details]).to eq([{code: "value_already_exist", field: "code", meta: {}}])
        end
      end
    end
  end

  describe "PUT /api/v2/plans/:plan_code/wallets/:code" do
    subject { put_with_token(organization, "/api/v2/plans/#{catalog_plan.code}/wallets/#{code}", {wallet: update_params}) }

    let(:code) { plan_wallet.code }
    let(:update_params) { {code: "credits", priority: 20, applies_to: {include: [{type: "fee_type", code: "fixed"}]}} }

    include_examples "requires API permission", "plan_wallet", "write"
    include_examples "requires the catalog_wallets flag"

    it "updates the wallet template" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:wallet]).to include(
        lago_id: plan_wallet.id, code: "credits", priority: 20, applies_to: {include: [{type: "fee_type", code: "fixed"}]}
      )
    end

    context "when the plan has a contract with its own copy of the wallet" do
      let(:contract) { create(:contract, organization:, catalog_plan:) }
      let(:catalog_wallet) { create(:catalog_wallet, organization:, contract:, customer: contract.customer, code: "ai_credits", priority: 10) }
      let(:update_params) { {priority: 20, tax_application: "tax_on_purchase"} }

      before { catalog_wallet }

      it "updates the template and leaves the contract's wallet unchanged" do
        expect { subject }.not_to change { catalog_wallet.reload.attributes }

        expect(response).to have_http_status(:success)
        expect(json[:wallet]).to include(priority: 20, tax_application: "tax_on_purchase")
      end

      context "when the code changes" do
        let(:update_params) { {code: "credits"} }

        it "returns a validation error on code" do
          subject

          expect(response).to have_http_status(:unprocessable_content)
          expect(json[:details]).to eq([{code: "plan_locked", field: "code", meta: {}}])
          expect(plan_wallet.reload.code).to eq("ai_credits")
        end
      end
    end

    context "with a rate amount" do
      let(:update_params) { {rate_amount: "1.0"} }

      it "returns a validation error on rate_amount" do
        subject

        expect(response).to have_http_status(:unprocessable_content)
        expect(json[:details]).to eq([{code: "not_supported", field: "rate_amount", meta: {}}])
      end
    end

    context "when it does not exist" do
      let(:code) { "unknown" }

      it "returns a not found error" do
        subject

        expect(response).to be_v2_not_found_error("wallet")
      end
    end
  end

  describe "DELETE /api/v2/plans/:plan_code/wallets/:code" do
    subject { delete_with_token(organization, "/api/v2/plans/#{catalog_plan.code}/wallets/#{code}") }

    let(:code) { plan_wallet.code }

    include_examples "requires API permission", "plan_wallet", "write"
    include_examples "requires the catalog_wallets flag"

    it "soft deletes the wallet template" do
      freeze_time do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:wallet]).to include(lago_id: plan_wallet.id, deleted_at: Time.current.iso8601(6))
        expect(catalog_plan.wallets).to be_empty
      end
    end

    context "when the plan has a contract with its own copy of the wallet" do
      let(:contract) { create(:contract, organization:, catalog_plan:) }
      let(:catalog_wallet) { create(:catalog_wallet, organization:, contract:, customer: contract.customer, code: "ai_credits") }

      before { catalog_wallet }

      it "deletes the template and keeps the contract's wallet" do
        subject

        expect(response).to have_http_status(:success)
        expect(catalog_wallet.reload).to be_kept
      end
    end

    context "when it does not exist" do
      let(:code) { "unknown" }

      it "returns a not found error" do
        subject

        expect(response).to be_v2_not_found_error("wallet")
      end
    end
  end
end
