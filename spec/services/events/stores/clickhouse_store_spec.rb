# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Events::Stores::ClickhouseStore, type: :service, clickhouse: true do
  subject(:event_store) do
    described_class.new(
      code:,
      subscription:,
      boundaries:,
      group:,
      event:,
    )
  end

  let(:billable_metric) { create(:billable_metric) }
  let(:organization) { billable_metric.organization }

  let(:customer) { create(:customer, organization:) }
  let(:subscription) { create(:subscription, customer:, started_at: DateTime.parse('2023-03-15')) }

  let(:code) { billable_metric.code }

  let(:boundaries) do
    {
      charges_from_datetime: subscription.started_at.beginning_of_day,
      charges_to_datetime: subscription.started_at.end_of_month.end_of_day,
    }
  end

  let(:group) { nil }
  let(:event) { nil }

  before { skip if ENV['LAGO_CLICKHOUSE_ENABLED'].blank? }

  describe '.events' do
    it 'returns a list of events' do
      expect(event_store.events).to eq([])
    end

    context 'with group' do
      let(:group) { create(:group, billable_metric:) }

      it 'returns a list of events' do
        expect(event_store.events).to eq([])
      end
    end
  end

  describe '.count' do
    it 'returns the number of unique events' do
      expect(event_store.count).to be_zero
    end
  end

  describe '.events_values' do
    it 'returns the value attached to each event' do
      expect(event_store.events_values).to eq([])
    end
  end

  describe '.max' do
    it 'returns the max value' do
      expect(event_store.max).to be_nil
    end
  end
end
