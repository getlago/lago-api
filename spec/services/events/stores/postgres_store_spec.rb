# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Events::Stores::PostgresStore, type: :service do
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
  let(:subscription) { create(:subscription, customer:, started_at: Time.zone.parse('2023-03-15')) }

  let(:code) { billable_metric.code }

  let(:boundaries) do
    {
      charges_from_datetime: subscription.started_at.beginning_of_day,
      charges_to_datetime: subscription.started_at.end_of_month.end_of_day,
    }
  end

  let(:group) { nil }
  let(:event) { nil }

  let(:events) do
    events = []

    5.times do |i|
      event = create(
        :event,
        organization:,
        external_subscription_id: subscription.external_id,
        external_customer_id: customer.external_id,
        code:,
        timestamp: boundaries[:from_datetime] + (i + 1).days,
        properties: {
          billable_metric.field_name => i + 1,
        },
      )

      if group && i.even?
        event.properties[group.key] = group.value
        event.save!
      end

      events << event
    end

    events
  end

  before { events }

  describe '.events' do
    it 'returns a list of events' do
      expect(event_store.events.count).to eq(5)
    end

    context 'with group' do
      let(:group) { create(:group, billable_metric:) }

      it 'returns a list of events' do
        expect(event_store.events.count).to eq(3)
      end
    end
  end

  describe '.count' do
    it 'returns the number of unique events' do
      expect(event_store.count).to eq(5)
    end
  end

  describe '.events_values' do
    it 'returns the value attached to each event' do
      event_store.aggregation_property = billable_metric.field_name
      event_store.numeric_property = true

      expect(event_store.events_values).to eq([1, 2, 3, 4, 5])
    end
  end

  describe '.max' do
    it 'returns the max value' do
      event_store.aggregation_property = billable_metric.field_name
      event_store.numeric_property = true

      expect(event_store.max).to eq(5)
    end
  end

  describe '.last' do
    it 'returns the last event' do
      event_store.aggregation_property = billable_metric.field_name
      event_store.numeric_property = true

      expect(event_store.last).to eq(5)
    end
  end
end
