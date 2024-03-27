# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::PaymentProviders::Destroy, type: :graphql do
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:payment_provider) { create(:stripe_provider, organization:) }

  let(:mutation) do
    <<-GQL
      mutation($input: DestroyPaymentProviderInput!) {
        destroyPaymentProvider(input: $input) { id }
      }
    GQL
  end

  it "deletes a payment provider" do
    result = execute_graphql(
      current_user: membership.user,
      query: mutation,
      variables: {
        input: {id: payment_provider.id}
      }
    )

    data = result["data"]["destroyPaymentProvider"]
    expect(data["id"]).to eq(payment_provider.id)
  end
end
