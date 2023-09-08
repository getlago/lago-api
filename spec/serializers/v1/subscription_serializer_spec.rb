# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ::V1::SubscriptionSerializer do
  subject(:serializer) { described_class.new(subscription, root_name: 'subscription', includes: %i[customer plan]) }

  let!(:subscription) { create(:subscription, ending_at: Time.current + 1.month) }

  it 'serializes the object' do
    result = JSON.parse(serializer.to_json)

    aggregate_failures do
      expect(result['subscription']).to include(
        'lago_id' => subscription.id,
        'external_id' => subscription.external_id,
        'lago_customer_id' => subscription.customer_id,
        'external_customer_id' => subscription.customer.external_id,
        'name' => subscription.name,
        'plan_code' => subscription.plan.code,
        'status' => subscription.status,
        'billing_time' => subscription.billing_time,
        'created_at' => subscription.created_at.iso8601,
        'ending_at' => subscription.ending_at.iso8601,
      )

      expect(result['subscription']['customer']['lago_id']).to be_present
      expect(result['subscription']['plan']['lago_id']).to be_present
    end
  end
end
