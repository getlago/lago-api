# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Events::Stores::PostgresStore, type: :service do
  subject(:event_store) do
    described_class.new(
      code:,
      subscription:,
      boundaries:,
      filters: { group:, grouped_by:, grouped_by_values: },
    )
  end

  let(:billable_metric) { create(:billable_metric, field_name: 'value') }
  let(:organization) { billable_metric.organization }

  let(:customer) { create(:customer, organization:) }
  let(:started_at) { Time.zone.parse('2023-03-15') }
  let(:subscription) { create(:subscription, customer:, started_at:) }

  let(:code) { billable_metric.code }

  let(:boundaries) do
    {
      from_datetime: started_at.beginning_of_day,
      to_datetime: started_at.end_of_month.end_of_day,
      charges_duration: 31,
    }
  end

  let(:group) { nil }
  let(:grouped_by) { nil }
  let(:grouped_by_values) { nil }

  let(:events) do
    events = []

    5.times do |i|
      event = build(
        :event,
        organization_id: organization.id,
        external_subscription_id: subscription.external_id,
        external_customer_id: customer.external_id,
        code:,
        timestamp: boundaries[:from_datetime] + (i + 1).days,
        properties: {
          billable_metric.field_name => i + 1,
        },
      )

      if i.even?
        event.properties[group.key] = group.value if group
        event.properties[grouped_by] = grouped_by_values[grouped_by] if grouped_by_values

        if grouped_by.present? && grouped_by_values.blank?
          grouped_by.each do |group|
            event.properties[group] = Faker::Lorem.word
          end
        end
      end

      event.save!

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

    context 'with grouped_by_values' do
      let(:grouped_by) { 'region' }
      let(:grouped_by_values) { { 'region' => 'europe' } }

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

  describe '.grouped_count' do
    let(:grouped_by) { %w[cloud] }

    it 'returns the number of unique events grouped by the provided group' do
      result = event_store.grouped_count

      expect(result.count).to eq(4)

      null_group = result.last
      expect(null_group[:group]).to eq([nil])
      expect(null_group[:value]).to eq(2)

      result[...-1].each do |row|
        expect(row[:group].count).to eq(1)
        expect(row[:value]).to eq(1)
      end
    end

    context 'with multiple groups' do
      let(:grouped_by) { %w[cloud region] }

      it 'returns the number of unique events grouped by the provided groups' do
        result = event_store.grouped_count

        expect(result.count).to eq(4)

        null_group = result.last
        expect(null_group[:group]).to eq([nil, nil])
        expect(null_group[:value]).to eq(2)

        result[...-1].each do |row|
          expect(row[:group].count).to eq(2)
          expect(row[:value]).to eq(1)
        end
      end
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

      expect(event_store.last_event).to eq(events.last)
    end
  end

  describe '.prorated_events_values' do
    it 'returns the value attached to each event prorated on the provided duration' do
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

  describe '.grouped_max' do
    let(:grouped_by) { %w[cloud] }

    before do
      event_store.aggregation_property = billable_metric.field_name
      event_store.numeric_property = true
    end

    it 'returns the max values grouped by the provided group' do
      result = event_store.grouped_max

      expect(result.count).to eq(4)

      null_group = result.last
      expect(null_group[:group]).to eq([nil])
      expect(null_group[:value]).to eq(4)

      result[...-1].each do |row|
        expect(row[:group].count).to eq(1)
      end
    end

    context 'with multiple groups' do
      let(:grouped_by) { %w[cloud region] }

      it 'returns the max values grouped by the provided groups' do
        result = event_store.grouped_max

        expect(result.count).to eq(4)

        null_group = result.last
        expect(null_group[:group]).to eq([nil, nil])
        expect(null_group[:value]).to eq(4)

        result[...-1].each do |row|
          expect(row[:group].count).to eq(2)
        end
      end
    end
  end

  describe '.last' do
    it 'returns the last event' do
      event_store.aggregation_property = billable_metric.field_name
      event_store.numeric_property = true

      expect(event_store.last).to eq(5)
    end
  end

  describe '.grouped_last' do
    let(:grouped_by) { %w[cloud] }

    before do
      event_store.aggregation_property = billable_metric.field_name
      event_store.numeric_property = true
    end

    it 'returns the last value for the provided group' do
      result = event_store.grouped_last

      expect(result.count).to eq(4)

      null_group = result.last
      expect(null_group[:group]).to eq([nil])
      expect(null_group[:value]).to eq(4)

      result[...-1].each do |row|
        expect(row[:group].count).to eq(1)
        expect(row[:value]).not_to be_nil
      end
    end

    context 'with multiple groups' do
      let(:grouped_by) { %w[cloud region] }

      it 'returns the last value for each provided groups' do
        result = event_store.grouped_last

        expect(result.count).to eq(4)

        null_group = result.last
        expect(null_group[:group]).to eq([nil, nil])
        expect(null_group[:value]).to eq(4)

        result[...-1].each do |row|
          expect(row[:group].count).to eq(2)
          expect(row[:value]).not_to be_nil
        end
      end
    end
  end

  describe '.sum' do
    it 'returns the sum of event values' do
      event_store.aggregation_property = billable_metric.field_name
      event_store.numeric_property = true

      expect(event_store.sum).to eq(15)
    end
  end

  describe '.grouped_sum' do
    let(:grouped_by) { %w[cloud] }

    before do
      event_store.aggregation_property = billable_metric.field_name
      event_store.numeric_property = true
    end

    it 'returns the sum of values grouped by the provided group' do
      result = event_store.grouped_sum

      expect(result.count).to eq(4)

      null_group = result.last
      expect(null_group[:group]).to eq([nil])
      expect(null_group[:value]).to eq(6)

      result[...-1].each do |row|
        expect(row[:group].count).to eq(1)
        expect(row[:value]).not_to be_nil
      end
    end

    context 'with multiple groups' do
      let(:grouped_by) { %w[cloud region] }

      it 'returns the sum of values grouped by the provided groups' do
        result = event_store.grouped_sum

        expect(result.count).to eq(4)

        null_group = result.last
        expect(null_group[:group]).to eq([nil, nil])
        expect(null_group[:value]).to eq(6)

        result[...-1].each do |row|
          expect(row[:group].count).to eq(2)
          expect(row[:value]).not_to be_nil
        end
      end
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
            value: e.properties[billable_metric.field_name],
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
      events = []

      events_values.each do |values|
        properties = { value: values[:value] }
        properties[:region] = values[:region] if values[:region]

        event = create(
          :event,
          organization_id: organization.id,
          external_subscription_id: subscription.external_id,
          external_customer_id: customer.external_id,
          code:,
          timestamp: values[:timestamp],
          properties:,
        )

        events << event
      end

      events
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
          { timestamp: Time.zone.parse('2023-03-01 00:00:00.000'), value: 1000, region: 'europe' },
        ]
      end

      it 'returns the weighted sum of event properties scoped to the group' do
        expect(event_store.weighted_sum.round(5)).to eq(1000.0)
      end
    end
  end
end
