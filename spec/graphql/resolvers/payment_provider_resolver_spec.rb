# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::PaymentProviderResolver do
  let_it_be(:organization) { create_default(:organization) }
  let_it_be(:user) { create_default(:user) }
  let(:required_permission) { "organization:integrations:view" }
  let(:organization) { membership.organization }
  let(:stripe_provider) { create(:stripe_provider, organization:) }
  let(:query) do
    <<~GQL
      query($paymentProviderId: ID!) {
        paymentProvider(id: $paymentProviderId) {
          ... on AdyenProvider {
            id
            code
            name
            __typename
          }
          ... on CashfreeProvider {
            id
            code
            name
            __typename
          }
          ... on GocardlessProvider {
            id
            code
            name
            __typename
          }
          ... on StripeProvider {
            id
            code
            name
            __typename
          }
        }
      }
    GQL
  end

  let_it_be(:membership) { create_default(:membership) }
  let_it_be(:customer) { create_default(:customer, organization:) }

  before do
    customer
    stripe_provider
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "organization:integrations:view"

  it "returns a single payment provider" do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query:,
      variables: {paymentProviderId: stripe_provider.id}
    )

    payment_provider_response = result["data"]["paymentProvider"]

    expect(payment_provider_response["id"]).to eq(stripe_provider.id)
    expect(payment_provider_response["code"]).to eq(stripe_provider.code)
    expect(payment_provider_response["name"]).to eq(stripe_provider.name)
  end
end
