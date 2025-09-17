# frozen_string_literal: true

require "rails_helper"

describe "Subscriptions Activation Scenario" do
  let(:organization) { create(:organization, webhook_url: nil) }

  let(:timezone) { "America/Bogota" }
  let(:customer) { create(:customer, organization:, timezone:) }

  let(:plan) do
    create(
      :plan,
      organization:,
      interval: "monthly",
      pay_in_advance: false
    )
  end

  let(:subscription_at) { DateTime.new(2023, 8, 24, 4, 17) }
  let(:creation_time) { DateTime.new(2023, 8, 24, 0, 7) }

  it "activates the subscription when it reaches its subscription date" do
    subscription = nil

    travel_to(creation_time) do
      create_subscription(
        {
          external_customer_id: customer.external_id,
          external_id: customer.external_id,
          plan_code: plan.code,
          billing_time: "calendar",
          subscription_at: subscription_at.iso8601
        }
      )

      subscription = customer.subscriptions.first
      expect(subscription).to be_pending
    end

    travel_to(subscription_at) do
      Subscriptions::ActivateService.new(timestamp: Time.current.to_i).activate_all_pending

      expect(subscription.reload).to be_active
    end
  end
end
