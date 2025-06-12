# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::PaymentProviders::Flutterwave::Create, type: :graphql do
  let(:required_permission) { "organization:integrations:create" }
  let(:membership) { create(:membership) }
  let(:public_key) { "FLWPUBK-xxxxxxxxx-X" }
  let(:secret_key) { "FLWSECK-xxxxxxxxx-X" }
  let(:encryption_key) { "xxxxxxxxxxxxxxxxxxxxxxxxx" }
  let(:code) { "flutterwave_1" }
  let(:name) { "Flutterwave 1" }
  let(:production) { false }
  let(:success_redirect_url) { Faker::Internet.url }

  let(:mutation) do
    <<-GQL
      mutation($input: AddFlutterwavePaymentProviderInput!) {
        addFlutterwavePaymentProvider(input: $input) {
          id,
          code,
          name,
          publicKey,
          secretKey,
          encryptionKey,
          production,
          successRedirectUrl
        }
      }
    GQL
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "organization:integrations:create"

  it "creates a flutterwave provider" do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: membership.organization,
      # You wouldn't have `create` without `view` permission
      # `view` is necessary to retrieve the created record in the response
      permissions: [required_permission, "organization:integrations:view"],
      query: mutation,
      variables: {
        input: {
          code:,
          name:,
          publicKey: public_key,
          secretKey: secret_key,
          encryptionKey: encryption_key,
          production:,
          successRedirectUrl: success_redirect_url
        }
      }
    )

    result_data = result["data"]["addFlutterwavePaymentProvider"]

    aggregate_failures do
      expect(result_data["id"]).to be_present
      expect(result_data["code"]).to eq(code)
      expect(result_data["name"]).to eq(name)
      expect(result_data["publicKey"]).to eq("••••••••…-X")
      expect(result_data["secretKey"]).to eq("••••••••…-X")
      expect(result_data["encryptionKey"]).to eq("••••••••…xxx")
      expect(result_data["production"]).to eq(production)
      expect(result_data["successRedirectUrl"]).to eq(success_redirect_url)
    end
  end
end
