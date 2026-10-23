# frozen_string_literal: true

require "rails_helper"

RSpec.describe "API v2 invoice routes left to v1" do
  let(:organization) { create(:organization, feature_flags: ["product_catalog"]) }
  let(:customer) { create(:customer, organization:) }
  let(:invoice) { create(:invoice, organization:, customer:, status: :draft) }

  [
    [:post, "/invoices"],
    [:post, "/invoices/preview"],
    [:post, "/invoices/:id/download"],
    [:post, "/invoices/:id/download_xml"],
    [:put, "/invoices/:id/sync_salesforce_id"]
  ].each do |verb, path|
    it "answers 404 to #{verb.upcase} #{path} on v2" do
      public_send(:"#{verb}_with_token", organization, "/api/v2#{path.sub(":id", invoice.id)}")

      expect(response).to be_not_found_error("resource")
      expect(response.headers["X-Lago-Endpoint-Status"]).to eq("beta")
    end
  end

  it "keeps serving the route on v1" do
    delete_with_token(organization, "/api/v1/invoices/#{invoice.id}")

    expect(response).to have_http_status(:success)
    expect(json[:invoice][:lago_id]).to eq(invoice.id)
  end
end
