# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::PaymentProviders::Braintree::Update do
  let(:required_permission) { "organization:integrations:update" }
  let(:membership) { create(:membership) }
  let(:braintree_provider) { create(:braintree_provider, organization: membership.organization) }
  let(:success_redirect_url) { Faker::Internet.url }

  let(:mutation) do
    <<-GQL
      mutation($input: UpdateBraintreePaymentProviderInput!) {
        updateBraintreePaymentProvider(input: $input) {
          id,
          successRedirectUrl
        }
      }
    GQL
  end

  before { braintree_provider }

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "organization:integrations:update"

  it "updates a braintree provider" do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: membership.organization,
      permissions: [required_permission, "organization:integrations:view"],
      query: mutation,
      variables: {
        input: {
          id: braintree_provider.id,
          successRedirectUrl: success_redirect_url
        }
      }
    )

    result_data = result["data"]["updateBraintreePaymentProvider"]

    expect(result_data["successRedirectUrl"]).to eq(success_redirect_url)
  end
end
