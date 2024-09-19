# frozen_string_literal: true

require 'rails_helper'

RSpec.describe EventsQuery, type: :query do
  subject(:events_query) { described_class.new(organization:, pagination:, filters:) }

  let(:organization) { create(:organization) }
  let(:pagination) { nil }
  let(:filters) { {} }

  let(:event) { create(:event, timestamp: 1.days.ago.to_date, organization:) }

  before { event }

  describe 'call' do
    it 'returns a list of events' do
      result = events_query.call

      aggregate_failures do
        expect(result).to be_success
        expect(result.events.count).to eq(1)
        expect(result.events).to eq([event])
      end
    end

    context 'with pagination' do
      let(:pagination) { {page: 2, limit: 10} }

      it 'applies the pagination' do
        result = events_query.call

        aggregate_failures do
          expect(result).to be_success
          expect(result.events.count).to eq(0)
          expect(result.events.current_page).to eq(2)
        end
      end
    end

    context 'with code filter' do
      let(:filters) { {code: event.code} }

      it 'applies the filter' do
        result = events_query.call

        aggregate_failures do
          expect(result).to be_success
          expect(result.events.count).to eq(1)
        end
      end
    end

    context 'with external subscription id filter' do
      let(:filters) { {external_customer_id: event.external_subscription_id} }

      it 'applies the filter' do
        result = events_query.call

        aggregate_failures do
          expect(result).to be_success
          expect(result.events.count).to eq(1)
        end
      end
    end

    context 'with timestamp from filter' do
      let(:filters) {
        {
          timestamp_from: 2.days.ago.iso8601.to_date.to_s,
          timestamp_to: Date.tomorrow.iso8601.to_date.to_s
        }
      }

      it 'applies the filter' do
        result = events_query.call

        aggregate_failures do
          expect(result).to be_success
          expect(result.events.count).to eq(1)
        end
      end
    end
  end
end
