# frozen_string_literal: true

require "rails_helper"

# The key minted for the AI agent carries the member's permissions, and the API enforces them
# even when the organization has not enabled API key permissions.
RSpec.describe "API with a member key" do
  let(:organization) { create(:organization, premium_integrations: []) }
  let(:role) { create(:role, organization:, permissions: %w[invoices:view invoices:update]) }
  let(:membership) { create(:membership, organization:, role:) }
  let(:api_key) { ApiKeys::CreateMemberKeyService.call!(membership:).api_key }
  let(:customer) { create(:customer, organization:) }
  let(:invoice) { create(:invoice, customer:, organization:) }
  let(:headers) { {"Authorization" => "Bearer #{api_key.value}", "Content-Type" => "application/json"} }

  it "lets the member read what they can view" do
    get "/api/v1/invoices/#{invoice.id}", headers: headers

    expect(response).to have_http_status(:success)
  end

  it "refuses a write the member's role does not allow" do
    post "/api/v1/invoices/#{invoice.id}/void", headers: headers

    expect(response).to have_http_status(:forbidden)
    expect(response.parsed_body["code"]).to eq("write_action_not_allowed_for_invoice")
  end

  it "refuses a resource the member cannot view" do
    get "/api/v1/plans", headers: headers

    expect(response).to have_http_status(:forbidden)
  end
end
