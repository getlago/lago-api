# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DailyUsages::ComputeService, type: :service do
  subject(:compute_service) { described_class.new(subscription:, timestamp:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:subscription) { create(:subscription, customer:) }

  let(:timestamp) { Time.zone.parse('2024-10-22 00:05:00') }

  describe '#call' do
    it 'creates a daily usage', aggregate_failures: true do
      expect { compute_service.call }.to change(DailyUsage, :count).by(1)

      daily_usage = DailyUsage.order(created_at: :asc).last
      expect(daily_usage).to have_attributes(
        organization_id: organization.id,
        customer_id: customer.id,
        subscription_id: subscription.id,
        external_subscription_id: subscription.external_id
        # TODO
      )
    end

    context 'when a daily usage already exists' do
      let(:existing_daily_usage) do
        create(:daily_usage, subscription:, organization:, customer:, created_at: timestamp)
      end

      before { existing_daily_usage }

      it 'returns the existing daily usage', aggregate_failure: true do
        result = compute_service.call

        expect(result).to be_success
        expect(result.daily_usage).to eq(existing_daily_usage)
      end
    end
  end
end
