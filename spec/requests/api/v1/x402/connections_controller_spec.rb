# frozen_string_literal: true

require "rails_helper"

describe Api::V1::X402::ConnectionsController, :premium do
  let(:organization) { create(:organization, feature_flags: ["x402_payments"]) }
  let(:evm_address) { "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed" }
  let(:svm_address) { "2wKupLR9q6wXYppw8Gr2NvWxKBUqm4PPJKkQfoxHDBg4" }

  include_context "with CDP credentials"

  before do
    stub_cdp_supported
    stub_cdp_account(:evm, evm_address)
    stub_cdp_account(:svm, svm_address)
  end

  shared_examples "an endpoint behind the x402_payments flag" do
    context "without the x402_payments flag" do
      let(:organization) { create(:organization) }

      it "returns a feature unavailable error" do
        subject
        expect(response).to have_http_status(:forbidden)
        expect(json[:code]).to eq("feature_unavailable")
      end
    end
  end

  describe "POST /api/v1/x402_connections" do
    subject { post_with_token(organization, "/api/v1/x402_connections", {x402_connection: params}) }

    let(:params) do
      {
        code: "my_cdp", name: "My CDP", networks: ["eip155:84532"], payout_addresses: {evm: evm_address},
        cdp_api_key_id:, cdp_api_key_secret:
      }
    end

    include_examples "requires API permission", "x402_connection", "write"
    include_examples "an endpoint behind the x402_payments flag"

    it "creates and renders the connection" do
      expect { subject }.to change { organization.x402_connections.count }.by(1)

      expect(response).to have_http_status(:ok)
      expect(json[:x402_connection]).to include(
        lago_organization_id: organization.id, code: "my_cdp", name: "My CDP", facilitator: "coinbase_cdp",
        asset: "usdc", networks: ["eip155:84532"], payout_addresses: {evm: evm_address}, auto_create_customers: true
      )
    end

    it "renders no secret" do
      subject
      expect(json[:x402_connection].keys.grep(/secret|cdp_api_key/)).to be_empty
    end

    context "when the API log is produced" do
      before { allow(Utils::ApiLog).to receive(:produce) }

      it "filters the CDP credentials out of the logged params" do
        subject
        expect(Utils::ApiLog).to have_received(:produce)
          .with(anything, anything, organization:, filtered_params: [:secret, :_key])
      end
    end

    context "with a lowercase EVM address" do
      let(:params) { super().merge(payout_addresses: {evm: evm_address.downcase}) }

      it "renders it checksummed" do
        subject
        expect(json[:x402_connection][:payout_addresses]).to eq(evm: evm_address)
      end

      it "looks up the checksummed address" do
        subject
        expect(a_request(:get, cdp_account_url(:evm, evm_address))).to have_been_made.once
      end
    end

    context "with a Solana network" do
      let(:params) { super().merge(networks: ["eip155:84532", "solana:EtWTRABZaYq6iMfeYKouRu166VU2xqa1"]) }

      context "without an SVM payout address" do
        it "returns a validation error" do
          subject
          expect(response).to have_http_status(:unprocessable_content)
          expect(json[:error_details]).to eq(payout_addresses: {svm: ["value_is_mandatory"]})
        end
      end
    end

    context "with mixed environments" do
      let(:params) do
        super().merge(networks: ["eip155:84532", "eip155:8453"])
      end

      it "returns a validation error" do
        subject
        expect(response).to have_http_status(:unprocessable_content)
        expect(json[:error_details]).to eq(networks: ["mixed_environments"])
      end
    end

    context "with a wrong checksum EVM address" do
      let(:params) { super().merge(payout_addresses: {evm: "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAeD"}) }

      it "returns a validation error" do
        subject
        expect(response).to have_http_status(:unprocessable_content)
        expect(json[:error_details]).to eq(payout_addresses: {evm: ["invalid_checksum"]})
      end

      it "calls CDP for nothing" do
        subject
        expect(a_request(:any, /api\.cdp\.coinbase\.com/)).not_to have_been_made
      end
    end

    context "with a string for networks" do
      let(:params) { super().merge(networks: "eip155:84532") }

      it "returns a validation error and creates nothing" do
        expect { subject }.not_to change { organization.x402_connections.count }

        expect(response).to have_http_status(:unprocessable_content)
        expect(json[:error_details]).to eq(networks: ["must_be_array"])
      end
    end

    context "with an existing code" do
      before { create(:x402_connection, organization:, code: "my_cdp") }

      it "returns a validation error" do
        subject
        expect(response).to have_http_status(:unprocessable_content)
        expect(json[:error_details]).to eq(code: ["value_already_exist"])
      end
    end

    context "when CDP rejects the credentials" do
      before { stub_cdp_supported(status: 401, body: "Unauthorized") }

      it "returns a validation error on cdp_api_key" do
        subject
        expect(response).to have_http_status(:unprocessable_content)
        expect(json[:error_details]).to eq(cdp_api_key: ["invalid_credentials"])
      end
    end

    context "when the payout address is not in the key's CDP project" do
      before { stub_cdp_account(:evm, evm_address, status: 404) }

      it "returns a validation error on payout_addresses" do
        subject
        expect(response).to have_http_status(:unprocessable_content)
        expect(json[:error_details]).to eq(payout_addresses: {evm: ["not_in_cdp_project"]})
      end

      it "persists nothing" do
        expect { subject }.not_to change(X402::Connection, :count)
      end
    end

    context "when CDP is unavailable" do
      before { stub_cdp_supported(status: 503, body: "") }

      it "returns a third-party error" do
        subject
        expect(response).to have_http_status(:unprocessable_content)
        expect(json).to include(code: "third_party_error", error_details: {third_party: "coinbase_cdp", thirdparty_error: "unavailable_error: supported: HTTP 503"})
      end
    end
  end

  describe "GET /api/v1/x402_connections" do
    subject { get_with_token(organization, "/api/v1/x402_connections") }

    let!(:connection) { create(:x402_connection, organization:) }

    before do
      create(:x402_connection, :discarded, organization:)
      create(:x402_connection)
    end

    include_examples "requires API permission", "x402_connection", "read"
    include_examples "an endpoint behind the x402_payments flag"

    it "lists only the kept connections of the organization" do
      subject
      expect(response).to have_http_status(:ok)
      expect(json[:x402_connections].map { |c| c[:lago_id] }).to eq([connection.id])
      expect(json[:meta]).to include(current_page: 1, total_count: 1)
    end
  end

  describe "GET /api/v1/x402_connections/:code" do
    subject { get_with_token(organization, "/api/v1/x402_connections/#{code}") }

    let(:connection) { create(:x402_connection, organization:) }
    let(:code) { connection.code }

    include_examples "requires API permission", "x402_connection", "read"
    include_examples "an endpoint behind the x402_payments flag"

    it "renders the connection without secrets" do
      subject
      expect(response).to have_http_status(:ok)
      expect(json[:x402_connection][:lago_id]).to eq(connection.id)
      expect(json[:x402_connection].keys.grep(/secret|cdp_api_key/)).to be_empty
    end

    context "with an unknown code" do
      let(:code) { "unknown" }

      it "returns a not found error" do
        subject
        expect(response).to be_not_found_error("x402_connection")
      end
    end

    context "with a discarded connection" do
      let(:connection) { create(:x402_connection, :discarded, organization:) }

      it "returns a not found error" do
        subject
        expect(response).to be_not_found_error("x402_connection")
      end
    end

    context "with another organization's connection" do
      let(:connection) { create(:x402_connection) }

      it "returns a not found error" do
        subject
        expect(response).to be_not_found_error("x402_connection")
      end
    end
  end

  describe "PUT /api/v1/x402_connections/:code" do
    subject { put_with_token(organization, "/api/v1/x402_connections/#{code}", {x402_connection: params}) }

    let(:connection) { create(:x402_connection, organization:, cdp_api_key_id:, cdp_api_key_secret:) }
    let(:code) { connection.code }
    let(:params) { {name: "Renamed"} }

    include_examples "requires API permission", "x402_connection", "write"
    include_examples "an endpoint behind the x402_payments flag"

    it "renders the new name and keeps the secrets" do
      subject
      expect(response).to have_http_status(:ok)
      expect(json[:x402_connection][:name]).to eq("Renamed")
      expect(connection.reload).to have_attributes(cdp_api_key_id:, cdp_api_key_secret:)
    end

    it "calls CDP for nothing" do
      subject
      expect(a_request(:any, /api\.cdp\.coinbase\.com/)).not_to have_been_made
    end

    context "when the new payout address is not in the key's CDP project" do
      let(:other_evm_address) { "0xfB6916095ca1df60bB79Ce92cE3Ea74c37c5d359" }
      let(:params) { {payout_addresses: {evm: other_evm_address}} }

      before { stub_cdp_account(:evm, other_evm_address, status: 404) }

      it "returns a validation error on payout_addresses" do
        subject
        expect(response).to have_http_status(:unprocessable_content)
        expect(json[:error_details]).to eq(payout_addresses: {evm: ["not_in_cdp_project"]})
      end
    end

    context "with invalid params" do
      let(:params) { {networks: ["unknown:1"]} }

      it "returns a validation error" do
        subject
        expect(response).to have_http_status(:unprocessable_content)
        expect(json[:error_details]).to eq(networks: ["value_is_invalid"])
      end
    end

    context "with a string for networks" do
      let(:params) { {networks: "eip155:8453"} }

      it "returns a validation error and keeps the networks" do
        expect { subject }.not_to change { connection.reload.networks }

        expect(response).to have_http_status(:unprocessable_content)
        expect(json[:error_details]).to eq(networks: ["must_be_array"])
      end

      context "with an unknown code" do
        let(:code) { "unknown" }

        it "returns a not found error" do
          subject
          expect(response).to be_not_found_error("x402_connection")
        end
      end
    end

    context "with a string for payout addresses" do
      let(:params) { {payout_addresses: evm_address} }

      it "returns a validation error and keeps the payout addresses" do
        expect { subject }.not_to change { connection.reload.payout_addresses }

        expect(response).to have_http_status(:unprocessable_content)
        expect(json[:error_details]).to eq(payout_addresses: ["value_is_invalid"])
      end
    end

    context "with an unknown code" do
      let(:code) { "unknown" }

      it "returns a not found error" do
        subject
        expect(response).to be_not_found_error("x402_connection")
      end
    end

    context "with a discarded connection" do
      let(:connection) { create(:x402_connection, :discarded, organization:) }

      it "returns a not found error" do
        subject
        expect(response).to be_not_found_error("x402_connection")
      end
    end
  end

  describe "DELETE /api/v1/x402_connections/:code" do
    subject { delete_with_token(organization, "/api/v1/x402_connections/#{code}") }

    let(:connection) { create(:x402_connection, organization:) }
    let(:code) { connection.code }

    include_examples "requires API permission", "x402_connection", "write"
    include_examples "an endpoint behind the x402_payments flag"

    it "discards and renders the connection" do
      subject
      expect(response).to have_http_status(:ok)
      expect(json[:x402_connection][:lago_id]).to eq(connection.id)
      expect(connection.reload).to be_discarded
    end

    context "with an unknown code" do
      let(:code) { "unknown" }

      it "returns a not found error" do
        subject
        expect(response).to be_not_found_error("x402_connection")
      end
    end
  end
end
