# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DailyUsages::ComputeService, type: :service do
  subject(:compute_service) { described_class.new(subscription:, timestamp:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:) }
  let(:subscription) { create(:subscription, :calendar, customer:, plan:, started_at: 1.year.ago) }

  let(:timestamp) { Time.zone.parse('2024-10-22 00:05:00') }

  describe '#call' do
    it 'creates a daily usage', aggregate_failures: true do
      travel_to(timestamp) do
        expect { compute_service.call }.to change(DailyUsage, :count).by(1)

        daily_usage = DailyUsage.order(created_at: :asc).last
        expect(daily_usage).to have_attributes(
          organization_id: organization.id,
          customer_id: customer.id,
          subscription_id: subscription.id,
          external_subscription_id: subscription.external_id,
          usage: Hash
        )
        expect(daily_usage.refreshed_at).to match_datetime(timestamp)
        expect(daily_usage.from_datetime).to match_datetime(timestamp.beginning_of_month)
        expect(daily_usage.to_datetime).to match_datetime(timestamp.end_of_month)
      end
    end

    context 'when a daily usage already exists' do
      let(:existing_daily_usage) do
        create(:daily_usage, subscription:, organization:, customer:, refreshed_at: timestamp)
      end

      before { existing_daily_usage }

      it 'returns the existing daily usage', aggregate_failure: true do
        result = compute_service.call

        expect(result).to be_success
        expect(result.daily_usage).to eq(existing_daily_usage)
      end

      context 'when the organization has a timezone' do
        let(:organization) { create(:organization, timezone: 'America/Sao_Paulo') }

        let(:existing_daily_usage) do
          create(:daily_usage, subscription:, organization:, customer:, refreshed_at: timestamp - 4.hours)
        end

        it 'takes the timezone into account' do
          result = compute_service.call

          expect(result).to be_success
          expect(result.daily_usage).to eq(existing_daily_usage)
        end
      end

      context 'when the customer has a timezone' do
        let(:customer) { create(:customer, organization:, timezone: 'America/Sao_Paulo') }

        let(:existing_daily_usage) do
          create(:daily_usage, subscription:, organization:, customer:, refreshed_at: timestamp - 4.hours)
        end

        it 'takes the timezone into account' do
          result = compute_service.call

          expect(result).to be_success
          expect(result.daily_usage).to eq(existing_daily_usage)
        end
      end
    end
  end
end
