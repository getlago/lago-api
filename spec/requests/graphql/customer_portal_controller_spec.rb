# frozen_string_literal: true

require "rails_helper"

RSpec.describe Graphql::CustomerPortalController, type: :request do
  let(:customer) { create(:customer) }
  let(:query) do
    <<~GQL
      query {
        customerPortalInvoices(limit: 5) {
          collection { id }
          metadata { currentPage, totalCount }
        }
      }
    GQL
  end
  let(:token) do
    ActiveSupport::MessageVerifier.new(ENV["SECRET_KEY_BASE"]).generate(customer.id, expires_in: 12.hours)
  end

  it "retrieves the correct end user and returns success status code" do
    post(
      "/customer_portal_graphql",
      headers: {
        "customer-portal-token" => token
      },
      params: {
        query:
      }
    )

    expect(response.status).to be(200)
  end
end
