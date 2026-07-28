# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::PaymentProviders::Paystack::Create do
  let(:required_permission) { "organization:integrations:create" }
  let(:membership) { create(:membership) }
  let(:secret_key) { "sk_test_#{SecureRandom.hex(24)}" }
  let(:code) { "paystack_1" }
  let(:name) { "Paystack 1" }
  let(:success_redirect_url) { Faker::Internet.url }

  let(:mutation) do
    <<-GQL
      mutation($input: AddPaystackPaymentProviderInput!) {
        addPaystackPaymentProvider(input: $input) {
          id
          code
          name
          secretKey
          successRedirectUrl
        }
      }
    GQL
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "organization:integrations:create"

  it "creates a paystack provider" do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: membership.organization,
      permissions: [required_permission, "organization:integrations:view"],
      query: mutation,
      variables: {input: {
        code:,
        name:,
        secretKey: secret_key,
        successRedirectUrl: success_redirect_url
      }}
    )

    result_data = result["data"]["addPaystackPaymentProvider"]

    expect(result_data["id"]).to be_present
    expect(result_data["code"]).to eq(code)
    expect(result_data["name"]).to eq(name)
    expect(result_data["secretKey"]).to start_with("••••••••…")
    expect(result_data["successRedirectUrl"]).to eq(success_redirect_url)
  end
end
