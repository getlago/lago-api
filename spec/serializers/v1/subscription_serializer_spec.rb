# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ::V1::SubscriptionSerializer do
  subject(:serializer) { described_class.new(subscription, root_name: 'subscription', includes: %i[customer plan]) }

  let!(:subscription) { create(:subscription) }

  it 'serializes the object' do
    result = JSON.parse(serializer.to_json)

    aggregate_failures do
      expect(result['subscription']['lago_id']).to eq(subscription.id)
      expect(result['subscription']['external_id']).to eq(subscription.external_id)
      expect(result['subscription']['lago_customer_id']).to eq(subscription.customer_id)
      expect(result['subscription']['external_customer_id']).to eq(subscription.customer.external_id)
      expect(result['subscription']['name']).to eq(subscription.name)
      expect(result['subscription']['plan_code']).to eq(subscription.plan.code)
      expect(result['subscription']['status']).to eq(subscription.status)
      expect(result['subscription']['billing_time']).to eq(subscription.billing_time)
      expect(result['subscription']['created_at']).to eq(subscription.created_at.iso8601)
      expect(result['subscription']['customer']['lago_id']).to eq(subscription.customer.id)
      expect(result['subscription']['plan']['lago_id']).to eq(subscription.plan.id)
    end
  end
end
