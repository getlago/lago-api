# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DailyUsages::ComputeAllService, type: :service do
  subject(:compute_service) { described_class.new(timestamp:) }

  let(:timestamp) { Time.zone.parse('2024-10-22 00:05:00') }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:subscription) { create(:subscription, customer:) }

  before { subscription }

  describe '#call' do
    context 'when LAGO_ENABLE_REVENUE_ANALYTICS is not present' do
      it 'does not enqueue any job' do
        expect(compute_service.call).to be_success
        expect(DailyUsages::ComputeJob).not_to have_been_enqueued
      end
    end

    context 'when LAGO_ENABLE_REVENUE_ANALYTICS is present' do
      before do
        allow(ENV).to receive(:[])
        allow(ENV).to receive(:[]).with('LAGO_ENABLE_REVENUE_ANALYTICS').and_return('true')
      end

      it 'enqueues a job to compute the daily usage' do
        expect(compute_service.call).to be_success
        expect(DailyUsages::ComputeJob).to have_been_enqueued.with(subscription, timestamp:)
      end

      context 'when subscription usage was already computed' do
        before { create(:daily_usage, subscription:, refreshed_at: timestamp + 2.minutes) }

        it 'does not enqueue any job' do
          expect(compute_service.call).to be_success
          expect(DailyUsages::ComputeJob).not_to have_been_enqueued
        end
      end

      context 'when the organization has a timezone' do
        let(:organization) { create(:organization, timezone: 'America/Sao_Paulo') }

        it 'takes the timezone into account' do
          expect(compute_service.call).to be_success
          expect(DailyUsages::ComputeJob).not_to have_been_enqueued
        end

        context 'when the day starts in the timezone' do
          let(:timestamp) { Time.zone.parse('2024-10-22 03:05:00') }

          it 'enqueues a job to compute the daily usage' do
            expect(compute_service.call).to be_success
            expect(DailyUsages::ComputeJob).to have_been_enqueued.with(subscription, timestamp:)
          end
        end
      end

      context 'when the customer has a timezone' do
        let(:customer) { create(:customer, timezone: 'America/Sao_Paulo') }

        it 'takes the timezone into account' do
          expect(compute_service.call).to be_success
          expect(DailyUsages::ComputeJob).not_to have_been_enqueued
        end

        context 'when the day starts in the timezone' do
          let(:timestamp) { Time.zone.parse('2024-10-22 03:05:00') }

          it 'enqueues a job to compute the daily usage' do
            expect(compute_service.call).to be_success
            expect(DailyUsages::ComputeJob).to have_been_enqueued.with(subscription, timestamp:)
          end
        end
      end
    end
  end
end
