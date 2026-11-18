# frozen_string_literal: true

require "rails_helper"

describe "Sandbox API key isolation" do
  let(:pair) { Organizations::CreateSelfServeService.call!(name: "Acme") }
  let(:production) { pair.organization }
  let(:sandbox) { pair.sandbox_organization }

  def create_customer(organization, external_id)
    post_with_token(organization, "/api/v1/customers", {customer: {external_id:, name: external_id}})
    expect(response).to have_http_status(:ok)
  end

  def fetch_customer(organization, external_id)
    get_with_token(organization, "/api/v1/customers/#{external_id}")
    response
  end

  it "keeps each organization's customers behind its own key" do
    create_customer(sandbox, "sandbox-customer")
    create_customer(production, "production-customer")

    expect(fetch_customer(sandbox, "sandbox-customer")).to have_http_status(:ok)
    expect(fetch_customer(production, "sandbox-customer")).to be_not_found_error("customer")
    expect(fetch_customer(production, "production-customer")).to have_http_status(:ok)
    expect(fetch_customer(sandbox, "production-customer")).to be_not_found_error("customer")
  end
end
