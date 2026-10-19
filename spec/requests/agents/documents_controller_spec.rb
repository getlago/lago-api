# frozen_string_literal: true

require "rails_helper"

RSpec.describe Agents::DocumentsController, :premium do
  subject { get("/agents/v1/#{storefront_id}/AUTH.md") }

  let(:organization) { create(:organization, premium_integrations: %w[agent_storefront]) }
  let(:storefront) { create(:agent_storefront_integration, organization:) }
  let(:storefront_id) { storefront.id }

  before do
    storefront.update!(resource_endpoint: "https://api.acme.example/v1")
  end

  it "renders the signup instructions of the connection" do
    subject

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("text/markdown")
    expect(response.body).to include("Sign up here to use #{storefront.name}.")
    expect(response.body).to include("- The API: `https://api.acme.example/v1`")
    expect(response.body).not_to include("Its documentation")
    expect(response.body).to include("POST `#{storefront.agent_url}/auth/challenges`")
  end

  context "with BILLING.md" do
    subject { get("/agents/v1/#{storefront_id}/BILLING.md") }

    it "renders the plans of the connection and how to enroll" do
      subject

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/markdown")
      expect(response.body).to include("# Billing: #{storefront.name}")
      expect(response.body).to include("POST `#{storefront.agent_url}/billing/enroll`")
    end
  end

  context "with an unknown connection" do
    let(:storefront_id) { SecureRandom.uuid }

    it "returns a not found error" do
      subject
      expect(response).to be_not_found_error("agent_storefront")
    end
  end

  context "without the premium integration" do
    let(:organization) { create(:organization, premium_integrations: []) }

    it "returns a not found error" do
      subject
      expect(response).to be_not_found_error("agent_storefront")
    end
  end
end
