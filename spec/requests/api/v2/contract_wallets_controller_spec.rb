# frozen_string_literal: true

require "rails_helper"

describe Api::V2::ContractWalletsController do
  let(:organization) { create(:organization, feature_flags:) }
  let(:feature_flags) { %w[product_catalog catalog_wallets] }
  let(:customer) { create(:customer, organization:, external_id: "acme", currency: "USD") }
  let(:contract) { create(:contract, organization:, customer:, external_id: "acme-pro") }
  let(:contract_wallet) do
    create(:catalog_wallet, organization:, customer:, contract:, code: "ai_credits", currency: "USD", priority: 10,
      balance_cents: 43_000, ongoing_balance_cents: 41_500)
  end
  let(:flat_keys) do
    %i[
      lago_id external_contract_id external_customer_id code name invoice_display_name currency tax_application priority
      applies_to top_up_min_amount_cents top_up_max_amount_cents balance_cents ongoing_balance_cents
      last_ongoing_balance_sync_at terminated_at created_at updated_at deleted_at
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

  describe "GET /api/v2/contracts/:external_id/wallets" do
    subject { get_with_token(organization, "/api/v2/contracts/#{external_id}/wallets") }

    let(:external_id) { contract.external_id }

    before do
      contract_wallet
      create(:catalog_wallet, organization:)
      create(:catalog_wallet, organization:, customer:, contract:, deleted_at: Time.current)
    end

    include_examples "requires API permission", "contract_wallet", "read"
    include_examples "requires the catalog_wallets flag"

    it "returns the contract's kept wallets only" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:contract_wallets].map { it[:lago_id] }).to eq([contract_wallet.id])
      expect(json[:contract_wallets].sole.keys).to eq(flat_keys)
      expect(json[:meta]).to eq(next_cursor: nil, prev_cursor: nil)
    end

    context "when another organization has a contract with the same external id" do
      let(:other_contract) { create(:contract, organization: create(:organization), external_id: "acme-pro") }

      before { create(:catalog_wallet, organization: other_contract.organization, contract: other_contract, code: "foreign") }

      it "leaves its wallets out" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:contract_wallets].map { it[:code] }).to eq(["ai_credits"])
      end
    end

    context "when wallets have selectors", :bullet do
      let(:other_contract_wallet) { create(:catalog_wallet, organization:, customer:, contract:, code: "support_credits", priority: 20) }

      before do
        product = create(:product, organization:)

        [contract_wallet, other_contract_wallet].each do |wallet|
          create(:catalog_wallet_selector, organization:, catalog_wallet: wallet)
          create(:catalog_wallet_selector, organization:, catalog_wallet: wallet, selector_type: "product", fee_type: nil, product:)
          create(:catalog_wallet_selector, organization:, catalog_wallet: wallet, selector_type: "product_category", fee_type: nil,
            product_category: product.product_category)
          create(:catalog_wallet_selector, organization:, catalog_wallet: wallet, selector_type: "product_filters", fee_type: nil,
            product_filter: create(:product_filter, organization:, product:))
        end
      end

      it "renders their scopes without a query per wallet or selector" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:contract_wallets].map { it[:applies_to][:include].map { |entry| entry[:type] }.sort })
          .to eq([%w[fee_type product product_category product_filters]] * 2)
      end
    end

    context "when the contract does not exist" do
      let(:external_id) { "unknown" }

      it "returns a not found error" do
        subject

        expect(response).to be_v2_not_found_error("contract")
      end
    end

    context "when the contract has ended" do
      let(:contract) { create(:contract, :terminated, organization:, customer:, external_id: "acme-pro") }

      it "returns its wallets" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:contract_wallets].map { it[:lago_id] }).to eq([contract_wallet.id])
      end
    end

    context "when an ended contract reuses the external id" do
      let(:ended_contract) do
        create(:contract, :terminated, organization:, customer:, external_id: "acme-pro", started_at: 2.months.ago)
      end

      before { create(:catalog_wallet, organization:, customer:, contract: ended_contract, code: "old_credits") }

      it "asks for the contract code" do
        subject

        expect(response).to have_http_status(:unprocessable_entity)
        expect(json).to eq(code: "validation_errors", details: [{code: "value_is_mandatory", field: "contract_code", meta: {}}])
      end

      context "with the contract code" do
        subject { get_with_token(organization, "/api/v2/contracts/#{external_id}/wallets", {contract_code: contract.code}) }

        it "returns the wallets of that contract only" do
          subject

          expect(response).to have_http_status(:success)
          expect(json[:contract_wallets].map { it[:code] }).to eq(["ai_credits"])
        end
      end
    end

    it_behaves_like "a cursor paginated v2 endpoint", collection: :contract_wallets, model: CatalogWallet do
      let(:paginated_path) { "/api/v2/contracts/#{contract.external_id}/wallets" }
      let(:create_paginated_record) { ->(created_at) { create(:catalog_wallet, organization:, customer:, contract:, created_at:) } }
    end

    it_behaves_like "a v2 list filtered on created_at", collection: :contract_wallets do
      let(:filtered_path) { "/api/v2/contracts/#{contract.external_id}/wallets" }
      let(:create_filtered_record) { ->(created_at) { create(:catalog_wallet, organization:, customer:, contract:, created_at:) } }
    end
  end

  describe "GET /api/v2/contracts/:external_id/wallets/:code" do
    subject { get_with_token(organization, "/api/v2/contracts/#{external_id}/wallets/#{code}", query) }

    let(:external_id) { contract.external_id }
    let(:code) { contract_wallet.code }
    let(:query) { {} }

    include_examples "requires API permission", "contract_wallet", "read"
    include_examples "requires the catalog_wallets flag"

    it "returns the wallet with its stored balances" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:contract_wallet]).to include(
        lago_id: contract_wallet.id, external_contract_id: "acme-pro", external_customer_id: "acme", code: "ai_credits",
        currency: "USD", tax_application: "tax_on_consumption", priority: 10, applies_to: {include: []},
        balance_cents: 43_000, ongoing_balance_cents: 41_500, last_ongoing_balance_sync_at: nil, terminated_at: nil,
        deleted_at: nil
      )
      expect(json[:contract_wallet].keys).to eq(flat_keys)
    end

    context "when the contract is pending" do
      let(:contract) { create(:contract, :pending, organization:, customer:, external_id: "acme-pro") }

      it "returns the wallet" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:contract_wallet][:lago_id]).to eq(contract_wallet.id)
      end
    end

    context "when the wallet has selectors", :bullet do
      before do
        product = create(:product, organization:, code: "api_calls")
        create(:catalog_wallet_selector, organization:, catalog_wallet: contract_wallet, selector_type: "product", fee_type: nil, product:)
        create(:catalog_wallet_selector, organization:, catalog_wallet: contract_wallet, selector_type: "product", fee_type: nil,
          product: create(:product, organization:, code: "storage"))
        create(:catalog_wallet_selector, organization:, catalog_wallet: contract_wallet, selector_type: "product_category", fee_type: nil,
          product_category: product.product_category)
        create(:catalog_wallet_selector, organization:, catalog_wallet: contract_wallet, selector_type: "product_filters", fee_type: nil,
          product_filter: create(:product_filter, organization:, product:))
      end

      it "renders its scope without a query per selector" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:contract_wallet][:applies_to][:include].map { it[:type] }).to match_array(%w[product product product_category product_filters])
      end
    end

    context "with the taxes and metadata expansions" do
      let(:query) { {expands: %w[taxes metadata]} }
      let(:tax) { create(:tax, organization:, code: "vat_20") }

      before do
        create(:catalog_wallet_applied_tax, organization:, catalog_wallet: contract_wallet, tax:)
        create(:item_metadata, organization:, owner: contract_wallet, value: {"team" => "growth"})
      end

      it "embeds them" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:contract_wallet].keys).to eq(flat_keys + %i[taxes metadata])
        expect(json[:contract_wallet][:taxes].map { it[:code] }).to eq(["vat_20"])
        expect(json[:contract_wallet][:metadata]).to eq(team: "growth")
      end
    end

    context "when it does not exist" do
      let(:code) { "unknown" }

      it "returns a not found error" do
        subject

        expect(response).to be_v2_not_found_error("contract_wallet")
      end
    end

    context "when it belongs to another contract" do
      let(:code) { create(:catalog_wallet, organization:, code: "other").code }

      it "returns a not found error" do
        subject

        expect(response).to be_v2_not_found_error("contract_wallet")
      end
    end

    context "when it is deleted" do
      let(:code) { create(:catalog_wallet, organization:, customer:, contract:, code: "old", deleted_at: Time.current).code }

      it "returns a not found error" do
        subject

        expect(response).to be_v2_not_found_error("contract_wallet")
      end
    end

    context "when the contract does not exist" do
      let(:external_id) { "unknown" }

      it "returns a not found error on the wallet" do
        subject

        expect(response).to be_v2_not_found_error("contract_wallet")
      end
    end

    context "when the contract has ended" do
      let(:contract) { create(:contract, :terminated, organization:, customer:, external_id: "acme-pro") }

      it "returns the wallet" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:contract_wallet][:lago_id]).to eq(contract_wallet.id)
      end
    end

    context "when an ended contract reuses the external id" do
      let(:ended_contract) do
        create(:contract, :terminated, organization:, customer:, external_id: "acme-pro", started_at: 2.months.ago)
      end
      let(:query) { {contract_code: contract.code} }

      before { create(:catalog_wallet, organization:, customer:, contract: ended_contract, code: "ai_credits") }

      it "returns the wallet of the contract with that code" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:contract_wallet][:lago_id]).to eq(contract_wallet.id)
      end
    end

    context "when it belongs to a contract of another organization with the same external id" do
      let(:other_contract) { create(:contract, organization: create(:organization), external_id: "acme-pro") }
      let(:code) { create(:catalog_wallet, organization: other_contract.organization, contract: other_contract, code: "foreign").code }

      before { contract }

      it "returns a not found error" do
        subject

        expect(response).to be_v2_not_found_error("contract_wallet")
      end
    end
  end

  describe "POST /api/v2/contracts/:external_id/wallets" do
    subject { post_with_token(organization, "/api/v2/contracts/#{external_id}/wallets", {contract_wallet: create_params}) }

    let(:external_id) { contract.external_id }
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

    include_examples "requires API permission", "contract_wallet", "write"
    include_examples "requires the catalog_wallets flag"

    it "adds an empty wallet to the contract" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:contract_wallet]).to include(
        external_contract_id: "acme-pro",
        external_customer_id: "acme",
        code: "ai_credits",
        name: "AI credits",
        invoice_display_name: "Prepaid credits",
        currency: "USD",
        tax_application: "tax_on_purchase",
        priority: 10,
        applies_to: {include: selectors},
        top_up_min_amount_cents: 1000,
        top_up_max_amount_cents: 50_000,
        balance_cents: 0,
        ongoing_balance_cents: 0,
        last_ongoing_balance_sync_at: nil,
        deleted_at: nil
      )
      expect(json[:contract_wallet].keys).to eq(flat_keys)
      expect(contract.wallets.sole).to have_attributes(id: json[:contract_wallet][:lago_id], taxes: [Tax.find_by(code: "vat_20")])
      expect(contract.wallets.sole.metadata.value).to eq({"team" => "growth"})
    end

    context "when the contract has a plan" do
      let(:catalog_plan) { create(:catalog_plan, organization:, currency: "USD") }
      let(:contract) { create(:contract, organization:, customer:, catalog_plan:, external_id: "acme-pro") }

      it "adds the wallet to the contract and leaves the plan without it" do
        expect { subject }.not_to change(catalog_plan.wallets, :count)

        expect(response).to have_http_status(:success)
        expect(contract.wallets.map(&:code)).to eq(["ai_credits"])
      end
    end

    context "with nested credit allocations" do
      let(:create_params) { super().merge(credit_allocations: [{code: "monthly", trigger: "billing_cycle", product_code: "api_calls", credit_amount: "100.00"}]) }

      it "adds the wallet without them" do
        expect { subject }.not_to change(CatalogWalletCreditAllocation, :count)

        expect(response).to have_http_status(:success)
      end
    end

    context "with a rate amount" do
      let(:create_params) { super().merge(rate_amount: "1.0") }

      it "ignores it" do
        expect { subject }.to change(CatalogWallet, :count).by(1)

        expect(response).to have_http_status(:success)
        expect(json[:contract_wallet].keys).to eq(flat_keys)
      end
    end

    context "when the contract does not exist" do
      let(:external_id) { "unknown" }

      it "returns a not found error" do
        subject

        expect(response).to be_v2_not_found_error("contract")
      end
    end

    context "when the contract belongs to another organization" do
      let(:contract) { create(:contract, organization: create(:organization), external_id: "acme-pro") }

      it "returns a not found error and adds nothing" do
        expect { subject }.not_to change(CatalogWallet, :count)

        expect(response).to be_v2_not_found_error("contract")
      end
    end

    [["a string", "ai_credits"], ["a list", [{code: "ai_credits"}]]].each do |description, root|
      context "when the contract_wallet root is #{description}" do
        let(:create_params) { root }

        it "returns a missing parameter error and adds nothing" do
          expect { subject }.not_to change(CatalogWallet, :count)

          expect(response).to have_http_status(:bad_request)
          expect(json).to eq(code: "missing_parameter", details: [{code: "missing", field: "contract_wallet", meta: {}}])
        end
      end
    end

    context "when a tax does not exist" do
      let(:create_params) { super().merge(tax_codes: ["unknown"]) }

      it "returns a not found error and adds nothing" do
        expect { subject }.not_to change(CatalogWallet, :count)

        expect(response).to be_v2_not_found_error("tax")
      end
    end

    describe "validations" do
      [
        ["a priority above 50", {priority: 51}, "value_is_out_of_range", "priority", {max: 50}],
        ["a currency other than the contract's", {currency: "EUR"}, "currency_does_not_match", "currency"],
        ["a scope that is not an object", {applies_to: [{type: "fee_type", code: "fixed"}]}, "value_is_invalid", "applies_to"],
        ["tax codes that are not a list", {tax_codes: "vat_20"}, "value_is_invalid", "tax_codes"],
        ["metadata that is not an object", {metadata: "growth"}, "value_is_invalid", "metadata"],
        ["an unknown tax application", {tax_application: "tax_free"}, "value_is_invalid", "tax_application", {allowed_values: %w[tax_on_consumption tax_on_purchase]}],
        ["a top-up minimum above the maximum", {top_up_min_amount_cents: 50_001}, "value_is_out_of_range", "top_up_max_amount_cents", {min: 50_001}],
        ["an excluded scope", {applies_to: {exclude: [{type: "fee_type", code: "fixed"}]}}, "not_supported", "applies_to.exclude"],
        ["a selector that does not exist", {applies_to: {include: [{type: "fee_type", code: "metered"}, {type: "product", code: "unknown"}]}}, "product_not_found", "applies_to.include[1].code"]
      ].each do |description, overrides, code, field, meta|
        context "with #{description}" do
          let(:create_params) { super().merge(overrides) }

          it "returns a validation error on #{field} and adds nothing" do
            expect { subject }.not_to change { [CatalogWallet.count, CatalogWalletSelector.count, CatalogWalletAppliedTax.count] }

            expect(response).to have_http_status(:unprocessable_content)
            expect(json[:code]).to eq("validation_errors")
            expect(json[:details]).to eq([{code:, field:, meta: meta || {}}])
          end
        end
      end

      context "with a code the contract already uses" do
        before { contract_wallet }

        it "returns a validation error on code" do
          subject

          expect(response).to have_http_status(:unprocessable_content)
          expect(json[:details]).to eq([{code: "value_already_exist", field: "code", meta: {}}])
        end
      end
    end
  end

  describe "PUT /api/v2/contracts/:external_id/wallets/:code" do
    subject { put_with_token(organization, "/api/v2/contracts/#{contract.external_id}/wallets/#{code}", {contract_wallet: update_params}) }

    let(:code) { contract_wallet.code }
    let(:update_params) { {name: "Credits", priority: 20, applies_to: {include: [{type: "fee_type", code: "fixed"}]}} }

    include_examples "requires API permission", "contract_wallet", "write"
    include_examples "requires the catalog_wallets flag"

    it "updates the wallet and keeps its balances" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:contract_wallet]).to include(
        lago_id: contract_wallet.id, code: "ai_credits", name: "Credits", priority: 20,
        applies_to: {include: [{type: "fee_type", code: "fixed"}]}, balance_cents: 43_000, ongoing_balance_cents: 41_500
      )
    end

    context "when the wallet has selectors", :bullet do
      let(:update_params) { {priority: 20} }

      before do
        product = create(:product, organization:, code: "api_calls")
        create(:catalog_wallet_selector, organization:, catalog_wallet: contract_wallet, selector_type: "product", fee_type: nil, product:)
        create(:catalog_wallet_selector, organization:, catalog_wallet: contract_wallet, selector_type: "product", fee_type: nil,
          product: create(:product, organization:, code: "storage"))
        create(:catalog_wallet_selector, organization:, catalog_wallet: contract_wallet, selector_type: "product_category", fee_type: nil,
          product_category: product.product_category)
        create(:catalog_wallet_selector, organization:, catalog_wallet: contract_wallet, selector_type: "product_filters", fee_type: nil,
          product_filter: create(:product_filter, organization:, product:))
      end

      it "renders its scope without a query per selector" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:contract_wallet][:applies_to][:include].map { it[:type] }).to match_array(%w[product product product_category product_filters])
      end
    end

    context "with a null metadata" do
      let(:update_params) { {metadata: nil} }

      before { create(:item_metadata, organization:, owner: contract_wallet, value: {"team" => "growth"}) }

      it "removes the metadata of the wallet" do
        subject

        expect(response).to have_http_status(:success)
        expect(contract_wallet.reload.metadata).to be_nil
      end
    end

    [
      ["the currency", {currency: "EUR"}, "currency"],
      ["the tax application", {tax_application: "tax_on_purchase"}, "tax_application"],
      ["the code", {code: "credits"}, "code"]
    ].each do |description, overrides, field|
      context "when #{description} changes" do
        let(:update_params) { {priority: 20}.merge(overrides) }

        it "returns a validation error on #{field} and changes nothing" do
          expect { subject }.not_to change { contract_wallet.reload.attributes }

          expect(response).to have_http_status(:unprocessable_content)
          expect(json[:details]).to eq([{code: "not_editable", field:, meta: {}}])
        end
      end
    end

    context "when the wallet comes from a plan" do
      let(:catalog_plan) { create(:catalog_plan, organization:, currency: "USD") }
      let(:contract) { create(:contract, organization:, customer:, catalog_plan:, external_id: "acme-pro") }
      let(:plan_wallet) { create(:plan_wallet, organization:, catalog_plan:, code: "ai_credits", priority: 10) }

      before { plan_wallet }

      it "updates the contract's wallet and leaves the template unchanged" do
        expect { subject }.not_to change { plan_wallet.reload.attributes }

        expect(response).to have_http_status(:success)
        expect(json[:contract_wallet]).to include(priority: 20)
      end
    end

    context "with a rate amount" do
      let(:update_params) { {rate_amount: "1.0", priority: 20} }

      it "ignores it" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:contract_wallet]).to include(lago_id: contract_wallet.id, priority: 20)
        expect(json[:contract_wallet].keys).to eq(flat_keys)
      end
    end

    context "when the contract belongs to another organization" do
      let(:contract) { create(:contract, organization: create(:organization), external_id: "acme-pro") }
      let(:contract_wallet) { create(:catalog_wallet, organization: contract.organization, contract:, code: "ai_credits", priority: 10) }

      it "returns a not found error and changes nothing" do
        expect { subject }.not_to change { contract_wallet.reload.attributes }

        expect(response).to be_v2_not_found_error("contract_wallet")
      end
    end

    [["a string", "ai_credits"], ["a list", [{priority: 20}]]].each do |description, root|
      context "when the contract_wallet root is #{description}" do
        let(:update_params) { root }

        it "returns a missing parameter error and changes nothing" do
          expect { subject }.not_to change { contract_wallet.reload.attributes }

          expect(response).to have_http_status(:bad_request)
          expect(json).to eq(code: "missing_parameter", details: [{code: "missing", field: "contract_wallet", meta: {}}])
        end
      end
    end

    context "when it does not exist" do
      let(:code) { "unknown" }

      it "returns a not found error" do
        subject

        expect(response).to be_v2_not_found_error("contract_wallet")
      end
    end
  end

  describe "DELETE /api/v2/contracts/:external_id/wallets/:code" do
    subject { delete_with_token(organization, "/api/v2/contracts/#{contract.external_id}/wallets/#{code}") }

    let(:contract_wallet) { create(:catalog_wallet, organization:, customer:, contract:, code: "ai_credits") }
    let(:code) { contract_wallet.code }

    include_examples "requires API permission", "contract_wallet", "write"
    include_examples "requires the catalog_wallets flag"

    it "soft deletes the wallet" do
      freeze_time do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:contract_wallet]).to include(lago_id: contract_wallet.id, deleted_at: Time.current.iso8601(6))
        expect(contract.wallets).to be_empty
      end
    end

    context "when the wallet holds credit" do
      let(:contract_wallet) { create(:catalog_wallet, organization:, customer:, contract:, code: "ai_credits", balance_cents: 43_000) }

      it "returns a forbidden error and keeps the wallet" do
        subject

        expect(response).to have_http_status(:forbidden)
        expect(json).to eq(code: "wallet_holds_credit", details: [])
        expect(contract_wallet.reload).to be_kept
      end
    end

    context "when the wallet has a credit allocation" do
      before { create(:catalog_wallet_credit_allocation, organization:, catalog_wallet: contract_wallet) }

      it "returns a forbidden error and keeps the wallet" do
        subject

        expect(response).to have_http_status(:forbidden)
        expect(json).to eq(code: "wallet_has_credit_allocations", details: [])
        expect(contract_wallet.reload).to be_kept
      end
    end

    context "when the contract belongs to another organization" do
      let(:contract) { create(:contract, organization: create(:organization), external_id: "acme-pro") }
      let(:contract_wallet) { create(:catalog_wallet, organization: contract.organization, contract:, code: "ai_credits") }

      it "returns a not found error and keeps the wallet" do
        subject

        expect(response).to be_v2_not_found_error("contract_wallet")
        expect(contract_wallet.reload).to be_kept
      end
    end

    context "when it does not exist" do
      let(:code) { "unknown" }

      it "returns a not found error" do
        subject

        expect(response).to be_v2_not_found_error("contract_wallet")
      end
    end
  end
end
