# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::Subscriptions::Update, type: :graphql do
  subject { execute_query(query:, input:) }

  let(:required_permission) { "subscriptions:update" }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }

  let(:subscription) do
    create(
      :subscription,
      organization:,
      subscription_at: Time.current + 3.days
    )
  end

  let(:query) do
    <<~GQL
      mutation($input: UpdateSubscriptionInput!) {
        updateSubscription(input: $input) {
          id
          name
          subscriptionAt
        }
      }
    GQL
  end
  let(:input) do
    {
      id: subscription.id,
      name: "New name"
    }
  end

  around { |test| lago_premium!(&test) }

  it_behaves_like "requires current user"
  it_behaves_like "requires permission", "subscriptions:update"

  it "updates an subscription" do
    result = subject

    result_data = result["data"]["updateSubscription"]

    expect(result_data["name"]).to eq("New name")
  end
end
