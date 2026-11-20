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
end
