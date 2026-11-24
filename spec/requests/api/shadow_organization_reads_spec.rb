# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::ShadowOrganizationReads, type: :request do
  let(:organization) { create(:organization) }
  let(:shadow_organization) { create(:shadow_organization) }
  let(:status) { "shadowing" }
  let(:v2_read_endpoints) { %w[contracts contracts/usage] }
  let(:shadow_customer) { create(:customer, organization: shadow_organization, external_id: "customer-1", currency: "EUR") }
  let(:contract) { create(:contract, organization: shadow_organization, customer: shadow_customer, external_id: "subscription-1") }
  let(:served_from) { response.headers[described_class::SERVED_FROM_HEADER] }

  before do
    create(:billing_engine_migration, organization:, shadow_organization:, status:, v2_read_endpoints:)
    contract
  end

  context "with a GET on an endpoint the migration opens" do
    it "returns the contract of the shadow organization" do
      get_with_token(organization, "/api/v2/contracts/subscription-1")

      expect(response).to have_http_status(:success)
      expect(json[:contract]).to include(lago_id: contract.id, external_id: "subscription-1", external_customer_id: "customer-1")
      expect(served_from).to eq("shadow_organization")
    end

    it "lists the contracts of the shadow organization only" do
      create(:contract, organization:, customer: create(:customer, organization:))

      get_with_token(organization, "/api/v2/contracts")

      expect(response).to have_http_status(:success)
      expect(json[:contracts].map { it[:lago_id] }).to eq([contract.id])
    end

    it "returns the current usage of the shadow contract" do
      get_with_token(organization, "/api/v2/contracts/subscription-1/current_usage")

      expect(response).to have_http_status(:success)
      expect(json[:current_usage]).to include(external_contract_id: "subscription-1", external_customer_id: "customer-1")
      expect(served_from).to eq("shadow_organization")
    end

    it "answers 404 for a record the shadow organization does not have" do
      get_with_token(organization, "/api/v2/contracts/not-copied")

      expect(response).to be_v2_not_found_error("contract")
    end

    context "with members in both organizations" do
      let(:membership) { create(:membership, organization:) }
      let(:shadow_membership) { create(:membership, organization: shadow_organization) }

      before do
        membership
        shadow_membership
        allow(CurrentContext).to receive(:api_key_id=).and_call_original
        allow(CurrentContext).to receive(:membership=).and_call_original
      end

      it "keeps the api key and the tracing membership of the v1 organization" do
        get_with_token(organization, "/api/v2/contracts/subscription-1")

        expect(response).to have_http_status(:success)
        expect(CurrentContext).to have_received(:api_key_id=).with(organization.api_keys.first.id)
        expect(CurrentContext).not_to have_received(:api_key_id=).with(shadow_organization.api_keys.first.id)
        expect(CurrentContext).to have_received(:membership=).with("membership/#{membership.id}")
        expect(CurrentContext).not_to have_received(:membership=).with("membership/#{shadow_membership.id}")
      end
    end
  end

  context "with a HEAD on an endpoint the migration opens" do
    it "answers it from the shadow organization like the GET" do
      headers = {}
      set_headers(organization, headers)
      head("/api/v2/contracts/subscription-1", headers:)

      expect(response).to have_http_status(:success)
      expect(served_from).to eq("shadow_organization")
    end

    it "logs the request on the v1 organization" do
      allow(Utils::ApiLog).to receive(:produce)
      headers = {}
      set_headers(organization, headers)
      head("/api/v2/contracts/subscription-1", headers:)

      expect(Utils::ApiLog).to have_received(:produce).with(anything, anything, hash_including(organization:))
    end
  end

  context "with a read-only POST on an endpoint the migration opens" do
    let(:v2_read_endpoints) { %w[credit_notes] }
    let(:shadow_invoice) { create(:invoice, organization: shadow_organization, customer: shadow_customer) }
    let(:v1_invoice) { create(:invoice, organization:, customer: create(:customer, organization:)) }

    it "estimates a credit note on the shadow organization and writes nothing" do
      expect { post_with_token(organization, "/api/v2/credit_notes/estimate", {credit_note: {invoice_id: shadow_invoice.id, items: []}}) }
        .not_to change(CreditNote, :count)

      expect(json[:code]).not_to eq("organization_migration_read_only")
      expect(served_from).to eq("shadow_organization")
    end

    it "logs the request on the v1 organization" do
      allow(Utils::ApiLog).to receive(:produce)

      post_with_token(organization, "/api/v2/credit_notes/estimate", {credit_note: {invoice_id: shadow_invoice.id, items: []}})

      expect(Utils::ApiLog).to have_received(:produce).with(anything, anything, hash_including(organization:))
    end

    it "does not find an invoice of the v1 organization" do
      post_with_token(organization, "/api/v2/credit_notes/estimate", {credit_note: {invoice_id: v1_invoice.id, items: []}})

      expect(response).to be_v2_not_found_error("invoice")
      expect(served_from).to eq("shadow_organization")
    end
  end

  context "with a read-only POST on an endpoint the migration does not open" do
    it "answers as before, from the v1 organization" do
      post_with_token(organization, "/api/v2/credit_notes/estimate", {credit_note: {invoice_id: SecureRandom.uuid, items: []}})

      expect(response).to have_http_status(:forbidden)
      expect(json[:code]).to eq("feature_unavailable")
      expect(served_from).to be_nil
    end
  end

  context "with a GET on an endpoint the migration opens when the shadow organization is not on the product catalog" do
    let(:shadow_organization) { create(:shadow_organization, feature_flags: []) }

    before { organization.update!(feature_flags: ["product_catalog"]) }

    it "refuses it on the flag of the shadow organization" do
      get_with_token(organization, "/api/v2/contracts/subscription-1")

      expect(response).to have_http_status(:forbidden)
      expect(json[:code]).to eq("feature_unavailable")
      expect(served_from).to eq("shadow_organization")
    end
  end

  context "with a write on an endpoint the migration opens" do
    let(:create_params) { {contract: {external_customer_id: "customer-1", external_id: "should-not-exist"}} }

    before { allow(Utils::ApiLog).to receive(:produce) }

    it "refuses it and writes nothing" do
      expect { post_with_token(organization, "/api/v2/contracts", create_params) }.not_to change(Contract, :count)

      expect(response).to have_http_status(:forbidden)
      expect(json).to eq(code: "organization_migration_read_only", details: [])
      expect(served_from).to be_nil
    end

    it "logs the refused request on the v1 organization" do
      post_with_token(organization, "/api/v2/contracts", create_params)

      expect(Utils::ApiLog).to have_received(:produce).with(anything, anything, hash_including(organization:))
    end

    it "refuses an update of a copied record" do
      expect { put_with_token(organization, "/api/v2/contracts/subscription-1", {contract: {name: "Renamed"}}) }
        .not_to change { contract.reload.name }

      expect(response).to have_http_status(:forbidden)
      expect(json[:code]).to eq("organization_migration_read_only")
    end
  end

  context "with a write on an endpoint the migration does not open" do
    it "refuses it" do
      expect { post_with_token(organization, "/api/v2/customers", {customer: {external_id: "new-customer"}}) }
        .not_to change(Customer, :count)

      expect(response).to have_http_status(:forbidden)
      expect(json[:code]).to eq("organization_migration_read_only")
    end
  end

  context "with a GET on an endpoint the migration does not open" do
    it "answers as before, from the v1 organization" do
      get_with_token(organization, "/api/v2/customers/customer-1")

      expect(response).to have_http_status(:forbidden)
      expect(json[:code]).to eq("feature_unavailable")
      expect(served_from).to be_nil
    end

    context "when the v1 organization is on the product catalog" do
      before { organization.update!(feature_flags: ["product_catalog"]) }

      it "reads the v1 organization" do
        get_with_token(organization, "/api/v2/customers/customer-1")

        expect(response).to be_v2_not_found_error("customer")
      end
    end
  end

  context "when the migration is paused" do
    let(:status) { "paused" }

    it "answers as before" do
      get_with_token(organization, "/api/v2/contracts/subscription-1")

      expect(response).to have_http_status(:forbidden)
      expect(json[:code]).to eq("feature_unavailable")
      expect(served_from).to be_nil
    end
  end

  context "when the migration is aborted" do
    let(:status) { "aborted" }

    it "answers as before" do
      post_with_token(organization, "/api/v2/contracts", {contract: {external_id: "should-not-exist"}})

      expect(response).to have_http_status(:forbidden)
      expect(json[:code]).to eq("feature_unavailable")
    end
  end

  context "without a migration" do
    let(:other_organization) { create(:organization) }

    it "answers as before" do
      get_with_token(other_organization, "/api/v2/contracts/subscription-1")

      expect(response).to have_http_status(:forbidden)
      expect(json[:code]).to eq("feature_unavailable")
      expect(served_from).to be_nil
    end
  end

  context "with the key of the shadow organization" do
    it "reads it without the shadow marker" do
      get_with_token(shadow_organization, "/api/v2/contracts/subscription-1")

      expect(response).to have_http_status(:success)
      expect(json[:contract][:lago_id]).to eq(contract.id)
      expect(served_from).to be_nil
    end
  end

  context "with the key of the v1 organization on a v1 endpoint" do
    let(:subscription) { create(:subscription, organization:, customer: create(:customer, organization:)) }

    it "reads the v1 organization", v2_timestamps: false do
      get_with_token(organization, "/api/v1/subscriptions/#{subscription.external_id}")

      expect(response).to have_http_status(:success)
      expect(json[:subscription][:lago_id]).to eq(subscription.id)
      expect(served_from).to be_nil
    end

    it "keeps writes open", v2_timestamps: false do
      put_with_token(organization, "/api/v1/subscriptions/#{subscription.external_id}", {subscription: {name: "Renamed"}})

      expect(response).to have_http_status(:success)
      expect(subscription.reload.name).to eq("Renamed")
    end
  end

  context "with the key of the v1 organization on a v1 controller served under /api/v2" do
    let(:subscription) { create(:subscription, organization:, customer: create(:customer, organization:)) }

    it "reads the v1 organization", v2_timestamps: false do
      get_with_token(organization, "/api/v2/subscriptions/#{subscription.external_id}")

      expect(response).to have_http_status(:success)
      expect(json[:subscription][:lago_id]).to eq(subscription.id)
    end
  end
end
