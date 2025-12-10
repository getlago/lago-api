# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::PaymentProviders::Braintree::Create do
  let(:required_permission) { "organization:integrations:create" }
  let(:membership) { create(:membership) }
  let(:public_key) { "public_key" }
  let(:private_key) { "private_key" }
  let(:code) { "braintree_1" }
  let(:name) { "Braintree 1" }
  let(:merchant_id) { "merchant" }
  let(:success_redirect_url) { Faker::Internet.url }

  let(:mutation) do
    <<-GQL
      mutation($input: AddBraintreePaymentProviderInput!) {
        addBraintreePaymentProvider(input: $input) {
          id,
          publicKey,
          privateKey,
          code,
          name,
          merchantId,
          successRedirectUrl
        }
      }
    GQL
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "organization:integrations:create"

  it "creates a braintree provider" do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: membership.organization,
      permissions: [required_permission, "organization:integrations:view"],
      query: mutation,
      variables: {
        input: {
          publicKey: public_key,
          privateKey: private_key,
          code:,
          name:,
          merchantId: merchant_id,
          successRedirectUrl: success_redirect_url
        }
      }
    )

    pp result

    result_data = result["data"]["addBraintreePaymentProvider"]

    aggregate_failures do
      expect(result_data["id"]).to be_present
      expect(result_data["publicKey"]).to eq("••••••••…key")
      expect(result_data["privateKey"]).to eq("••••••••…key")
      expect(result_data["code"]).to eq(code)
      expect(result_data["name"]).to eq(name)
      expect(result_data["merchantId"]).to eq(merchant_id)
      expect(result_data["successRedirectUrl"]).to eq(success_redirect_url)
    end
  end
end
