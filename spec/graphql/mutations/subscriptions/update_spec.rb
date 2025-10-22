# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::Subscriptions::Update do
  subject { execute_query(query:, input:) }

  let(:required_permission) { "subscriptions:update" }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:plan) { create(:plan, organization:) }
  let(:fixed_charge) { create(:fixed_charge, plan:) }

  let(:subscription) do
    create(
      :subscription,
      organization:,
      plan:,
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
          plan {
            fixedCharges {
              invoiceDisplayName
              units
            }
          }
        }
      }
    GQL
  end
  let(:input) do
    {
      id: subscription.id,
      name: "New name",
      planOverrides: {
        fixedCharges: [
          {
            id: fixed_charge.id,
            invoiceDisplayName: "NEW fixed charge display name",
            units: "99",
            applyUnitsImmediately: true
          }
        ]
      }
    }
  end

  around { |test| lago_premium!(&test) }

  before do
    plan
    fixed_charge
    subscription
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires permission", "subscriptions:update"

  it "updates an subscription" do
    result = subject

    result_data = result["data"]["updateSubscription"]

    expect(result_data["name"]).to eq("New name")

    expect(result_data["plan"]["fixedCharges"].first).to include(
      "invoiceDisplayName" => "NEW fixed charge display name",
      "units" => "99"
    )
  end

  context "when subscription is active" do
    let(:subscription) { create(:subscription, plan:, organization:) }

    it "emits a fixed charge event" do
      expect { subject }.to change(FixedChargeEvent, :count).by(1)

      expect(FixedChargeEvent.first).to have_attributes(units: BigDecimal("99"))
    end
  end
end
