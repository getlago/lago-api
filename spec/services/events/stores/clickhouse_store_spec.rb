# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Events::Stores::ClickhouseStore, type: :service, clickhouse: true do
  subject(:event_store) do
    described_class.new(
      code:,
      subscription:,
      boundaries:,
      filters: { group: },
    )
  end

  let(:billable_metric) { create(:billable_metric, field_name: 'value') }
  let(:organization) { billable_metric.organization }

  let(:customer) { create(:customer, organization:) }
  let(:subscription) { create(:subscription, customer:, started_at:) }

  let(:started_at) { DateTime.parse('2023-03-15') }
  let(:code) { billable_metric.code }

  let(:boundaries) do
    {
      from_datetime: subscription.started_at.beginning_of_day,
      to_datetime: subscription.started_at.end_of_month.end_of_day,
      charges_duration: 31,
    }
  end

  let(:group) { nil }

  let(:events) do
    events = []

    5.times do |i|
      properties = { billable_metric.field_name => i + 1 }
      properties[group.key.to_s] = group.value.to_s if group && i.even?

      events << Clickhouse::EventsRaw.create!(
        transaction_id: SecureRandom.uuid,
        organization_id: organization.id,
        external_subscription_id: subscription.external_id,
        external_customer_id: customer.external_id,
        code:,
        timestamp: boundaries[:from_datetime] + (i + 1).days,
        properties:,
      )
    end

    events
  end

  # NOTE: this does not include test with real values yet as we have to figure out
  #       how to add factories of fixtures in spec env and to setup clickhouse on the CI
  before do
    if ENV['LAGO_CLICKHOUSE_ENABLED'].blank?
      skip
    else
      events
    end
  end

  after do
    next if ENV['LAGO_CLICKHOUSE_ENABLED'].blank?

    Clickhouse::EventsRaw.connection.execute('TRUNCATE TABLE events_raw')
  end

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

  describe '.last_event' do
    it 'returns the last event' do
      event_store.aggregation_property = billable_metric.field_name
      event_store.numeric_property = true

      expect(event_store.last_event.transaction_id).to eq(events.last.transaction_id)
    end
  end

  describe '.prorated_events_values' do
    it 'returns the values attached to each event with prorata on period duration' do
      event_store.aggregation_property = billable_metric.field_name
      event_store.numeric_property = true

      expect(event_store.prorated_events_values(31).map { |v| v.round(3) }).to eq(
        [0.516, 0.968, 1.355, 1.677, 1.935],
      )
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

  describe '.sum' do
    it 'returns the sum of event properties' do
      event_store.aggregation_property = billable_metric.field_name
      event_store.numeric_property = true

      expect(event_store.sum).to eq(15)
    end
  end

  describe '.prorated_sum' do
    it 'returns the prorated sum of event properties' do
      event_store.aggregation_property = billable_metric.field_name
      event_store.numeric_property = true

      expect(event_store.prorated_sum(period_duration: 31).round(5)).to eq(6.45161)
    end

    context 'with persisted_duration' do
      it 'returns the prorated sum of event properties' do
        event_store.aggregation_property = billable_metric.field_name
        event_store.numeric_property = true

        expect(event_store.prorated_sum(period_duration: 31, persisted_duration: 10).round(5)).to eq(4.83871)
      end
    end
  end

  describe '.sum_date_breakdown' do
    it 'returns the sum grouped by day' do
      event_store.aggregation_property = billable_metric.field_name
      event_store.numeric_property = true

      expect(event_store.sum_date_breakdown).to eq(
        events.map do |e|
          {
            date: e.timestamp.to_date,
            value: e.properties[billable_metric.field_name].to_f,
          }
        end,
      )
    end
  end

  describe '.weighted_sum' do
    let(:started_at) { Time.zone.parse('2023-03-01') }

    let(:events_values) do
      [
        { timestamp: Time.zone.parse('2023-03-01 00:00:00.000'), value: 2 },
        { timestamp: Time.zone.parse('2023-03-01 01:00:00'), value: 3 },
        { timestamp: Time.zone.parse('2023-03-01 01:30:00'), value: 1 },
        { timestamp: Time.zone.parse('2023-03-01 02:00:00'), value: -4 },
        { timestamp: Time.zone.parse('2023-03-01 04:00:00'), value: -2 },
        { timestamp: Time.zone.parse('2023-03-01 05:00:00'), value: 10 },
        { timestamp: Time.zone.parse('2023-03-01 05:30:00'), value: -10 },
      ]
    end

    let(:events) do
      events_values.map do |values|
        properties = { value: values[:value] }
        properties[:region] = values[:region] if values[:region]

        Clickhouse::EventsRaw.create!(
          transaction_id: SecureRandom.uuid,
          organization_id: organization.id,
          external_subscription_id: subscription.external_id,
          external_customer_id: customer.external_id,
          code:,
          timestamp: values[:timestamp],
          properties:,
        )
      end
    end

    before do
      event_store.aggregation_property = billable_metric.field_name
      event_store.numeric_property = true
    end

    it 'returns the weighted sum of event properties' do
      expect(event_store.weighted_sum.round(5)).to eq(0.02218)
    end

    context 'with a single event' do
      let(:events_values) do
        [
          { timestamp: Time.zone.parse('2023-03-01 00:00:00.000'), value: 1000 },
        ]
      end

      it 'returns the weighted sum of event properties' do
        expect(event_store.weighted_sum.round(5)).to eq(1000.0)
      end
    end

    context 'with no events' do
      let(:events_values) { [] }

      it 'returns the weighted sum of event properties' do
        expect(event_store.weighted_sum.round(5)).to eq(0.0)
      end
    end

    context 'with events with the same timestamp' do
      let(:events_values) do
        [
          { timestamp: Time.zone.parse('2023-03-01 00:00:00.000'), value: 3 },
          { timestamp: Time.zone.parse('2023-03-01 00:00:00.000'), value: 3 },
        ]
      end

      it 'returns the weighted sum of event properties' do
        expect(event_store.weighted_sum.round(5)).to eq(6.0)
      end
    end

    context 'with initial value' do
      let(:initial_value) { 1000 }

      it 'uses the initial value in the aggregation' do
        expect(event_store.weighted_sum(initial_value:).round(5)).to eq(1000.02218)
      end

      context 'without events' do
        let(:events_values) { [] }

        it 'uses only the initial value in the aggregation' do
          expect(event_store.weighted_sum(initial_value:).round(5)).to eq(1000.0)
        end
      end
    end

    context 'with group' do
      let(:group) { create(:group, billable_metric:, key: 'region', value: 'europe') }

      let(:events_values) do
        [
          { timestamp: Time.zone.parse('2023-03-01 00:00:00.000'), value: 1000, region: group.value },
        ]
      end

      it 'returns the weighted sum of event properties scoped to the group' do
        expect(event_store.weighted_sum.round(5)).to eq(1000.0)
      end
    end
  end
end
