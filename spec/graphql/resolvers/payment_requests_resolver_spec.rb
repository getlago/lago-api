# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::PaymentRequestsResolver, type: :graphql do
  let(:required_permission) { "payment_requests:view" }
  let(:query) do
    <<~GQL
      query {
        paymentRequests(limit: 5) {
          collection {
            id
            amountCents
            customer { id }
            invoices { id }
          }
          metadata { currentPage, totalCount }
        }
      }
    GQL
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization:) }
  let(:payment_request) { create(:payment_request, organization:, customer:) }

  before do
    payment_request
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "payment_requests:view"

  it "returns a list of payment_requests", :aggregate_failures do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query:
    )

    payment_requests_response = result["data"]["paymentRequests"]

    expect(payment_requests_response["collection"].count).to eq(organization.payment_requests.count)
    expect(payment_requests_response["collection"].first["id"]).to eq(payment_request.id)
    expect(payment_requests_response["collection"].first["amountCents"]).to eq(payment_request.amount_cents.to_s)
    expect(payment_requests_response["collection"].first["customer"]["id"]).to eq(customer.id)
    expect(payment_requests_response["collection"].first["invoices"]).to eq([])
  end
end
