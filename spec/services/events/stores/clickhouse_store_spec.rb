# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Events::Stores::ClickhouseStore, type: :service, clickhouse: true do
  subject(:event_store) do
    described_class.new(
      code:,
      subscription:,
      boundaries:,
      filters: {
        grouped_by:,
        grouped_by_values:,
        matching_filters:,
        ignored_filters:
      }
    )
  end

  let(:billable_metric) { create(:billable_metric, field_name: 'value', code: 'bm:code') }
  let(:organization) { billable_metric.organization }

  let(:customer) { create(:customer, organization:) }
  let(:subscription) { create(:subscription, customer:, started_at:) }

  let(:started_at) { DateTime.parse('2023-03-15') }
  let(:code) { billable_metric.code }

  let(:boundaries) do
    {
      from_datetime: subscription.started_at.beginning_of_day,
      to_datetime: subscription.started_at.end_of_month.end_of_day,
      charges_duration: 31
    }
  end

  let(:grouped_by) { nil }
  let(:grouped_by_values) { nil }
  let(:matching_filters) { {} }
  let(:ignored_filters) { [] }

  let(:events) do
    events = []

    5.times do |i|
      properties = {billable_metric.field_name => i + 1}

      if i.even?
        matching_filters.each { |key, values| properties[key] = values.first }

        if grouped_by_values.present?
          grouped_by_values.each { |grouped_by, value| properties[grouped_by] = value }
        elsif grouped_by.present?
          grouped_by.each do |group|
            properties[group] = "#{Faker::Fantasy::Tolkien.character.delete("'")}_#{i}"
          end
        end
      end

      (ignored_filters.first || {}).each { |key, values| properties[key] = values.first } if i.zero?

      events << Clickhouse::EventsRaw.create!(
        transaction_id: SecureRandom.uuid,
        organization_id: organization.id,
        external_subscription_id: subscription.external_id,
        external_customer_id: customer.external_id,
        code:,
        timestamp: boundaries[:from_datetime] + (i + 1).days,
        properties:,
        precise_total_amount_cents: i + 1
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

    context 'with grouped_by_values' do
      let(:grouped_by_values) { {'region' => 'europe'} }

      it 'returns a list of events' do
        expect(event_store.events.count).to eq(3)
      end

      context 'when grouped_by_values value is nil' do
        let(:grouped_by_values) { {'region' => nil} }

        it 'returns a list of events' do
          expect(event_store.events.count).to eq(5)
        end
      end
    end

    context 'with filters' do
      let(:matching_filters) { {'region' => ['europe'], 'country' => ['france']} }
      let(:ignored_filters) { [{'city' => ['paris']}, {'city' => ['londons'], 'country' => ['united kingdom']}] }

      it 'returns a list of events' do
        expect(event_store.events.count).to eq(2) # 1st event is ignored
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

      null_group = result.find { |v| v[:groups]['cloud'].nil? }
      expect(null_group[:value]).to eq(2)

      result.each do |row|
        next if row[:groups]['cloud'].nil?

        expect(row[:groups]['cloud']).not_to be_nil
        expect(row[:value]).to eq(1)
      end
    end

    context 'with multiple groups' do
      let(:grouped_by) { %w[cloud region] }

      it 'returns the number of unique events grouped by the provided groups' do
        result = event_store.grouped_count

        expect(result.count).to eq(4)

        null_group = result.find { |v| v[:groups]['cloud'].nil? }
        expect(null_group[:groups]['region']).to be_nil
        expect(null_group[:value]).to eq(2)

        result[...-1].each do |row|
          next if row[:groups]['cloud'].nil?

          expect(row[:groups]['cloud']).not_to be_nil
          expect(row[:groups]['region']).not_to be_nil
          expect(row[:value]).to eq(1)
        end
      end
    end
  end

  describe '#sum_precise_total_amount_cents' do
    it 'returns the sum of precise_total_amount_cent values' do
      expect(event_store.sum_precise_total_amount_cents).to eq(15)
    end
  end

  describe '#grouped_sum_precise_total_amount_cents' do
    let(:grouped_by) { %w[cloud] }

    it 'returns the sum of values grouped by the provided group' do
      result = event_store.grouped_sum_precise_total_amount_cents

      expect(result.count).to eq(4)

      null_group = result.find { |v| v[:groups]['cloud'].nil? }
      expect(null_group[:value]).to eq(6)

      result[...-1].each do |row|
        next if row[:groups]['cloud'].nil?

        expect(row[:groups]['cloud']).not_to be_nil
        expect(row[:value]).not_to be_nil
      end
    end

    context 'with multiple groups' do
      let(:grouped_by) { %w[cloud region] }

      it 'returns the sum of values grouped by the provided groups' do
        result = event_store.grouped_sum_precise_total_amount_cents

        expect(result.count).to eq(4)

        null_group = result.find { |v| v[:groups]['cloud'].nil? }
        expect(null_group[:groups]['region']).to be_nil
        expect(null_group[:value]).to eq(6)

        result[...-1].each do |row|
          next if row[:groups]['cloud'].nil?

          expect(row[:groups]['cloud']).not_to be_nil
          expect(row[:groups]['region']).not_to be_nil
          expect(row[:value]).not_to be_nil
        end
      end
    end
  end

  describe '#active_unique_property?' do
    before { event_store.aggregation_property = billable_metric.field_name }

    it 'returns false when no previous events exist' do
      event = ::Clickhouse::EventsRaw.create!(
        organization_id: organization.id,
        external_subscription_id: subscription.external_id,
        external_customer_id: customer.external_id,
        code:,
        timestamp: (boundaries[:from_datetime] + 2.days).end_of_day,
        properties: {
          billable_metric.field_name => SecureRandom.uuid
        }
      )

      expect(event_store).not_to be_active_unique_property(event)
    end

    context 'when event is already active' do
      it 'returns true if the event property is active' do
        ::Clickhouse::EventsRaw.create!(
          organization_id: organization.id,
          external_subscription_id: subscription.external_id,
          external_customer_id: customer.external_id,
          code:,
          timestamp: (boundaries[:from_datetime] + 2.days).end_of_day,
          properties: {
            billable_metric.field_name => 2
          }
        )

        event = ::Clickhouse::EventsRaw.create!(
          organization_id: organization.id,
          external_subscription_id: subscription.external_id,
          external_customer_id: customer.external_id,
          code:,
          timestamp: (boundaries[:from_datetime] + 3.days).end_of_day,
          properties: {
            billable_metric.field_name => 2
          }
        )

        expect(event_store).to be_active_unique_property(event)
      end
    end

    context 'with a previous removed event' do
      it 'returns false' do
        ::Clickhouse::EventsRaw.create!(
          organization_id: organization.id,
          external_subscription_id: subscription.external_id,
          external_customer_id: customer.external_id,
          code:,
          timestamp: (boundaries[:from_datetime] + 2.days).end_of_day,
          properties: {
            billable_metric.field_name => 2,
            :operation_type => 'remove'
          }
        )

        event = ::Clickhouse::EventsRaw.create!(
          organization_id: organization.id,
          external_subscription_id: subscription.external_id,
          external_customer_id: customer.external_id,
          code:,
          timestamp: (boundaries[:from_datetime] + 3.days).end_of_day,
          properties: {
            billable_metric.field_name => 2
          }
        )

        expect(event_store).not_to be_active_unique_property(event)
      end
    end
  end

  describe '#unique_count' do
    it 'returns the number of unique active event properties' do
      Clickhouse::EventsRaw.create!(
        transaction_id: SecureRandom.uuid,
        organization_id: organization.id,
        external_subscription_id: subscription.external_id,
        external_customer_id: customer.external_id,
        code:,
        timestamp: boundaries[:from_datetime] + 3.days,
        properties: {
          billable_metric.field_name => 2,
          :operation_type => 'remove'
        }
      )

      event_store.aggregation_property = billable_metric.field_name

      expect(event_store.unique_count).to eq(4) # 5 events added / 1 removed
    end
  end

  describe '#prorated_unique_count' do
    it 'returns the number of unique active event properties' do
      Clickhouse::EventsRaw.create!(
        transaction_id: SecureRandom.uuid,
        organization_id: organization.id,
        external_subscription_id: subscription.external_id,
        external_customer_id: customer.external_id,
        code:,
        timestamp: boundaries[:from_datetime] + 1.day,
        properties: {
          billable_metric.field_name => 2
        }
      )

      Clickhouse::EventsRaw.create!(
        transaction_id: SecureRandom.uuid,
        organization_id: organization.id,
        external_subscription_id: subscription.external_id,
        external_customer_id: customer.external_id,
        code:,
        timestamp: (boundaries[:from_datetime] + 1.day).end_of_day,
        properties: {
          billable_metric.field_name => 2,
          :operation_type => 'remove'
        }
      )

      event_store.aggregation_property = billable_metric.field_name

      # NOTE: Events calculation: 16/31 + 1/31 + + 15/31 + 14/31 + 13/31 + 12/31
      expect(event_store.prorated_unique_count.round(3)).to eq(2.29)
    end
  end

  describe '#grouped_unique_count' do
    let(:grouped_by) { %w[agent_name other] }
    let(:started_at) { Time.zone.parse('2023-03-01') }

    let(:events) do
      [
        Clickhouse::EventsRaw.create!(
          organization_id: organization.id,
          external_subscription_id: subscription.external_id,
          external_customer_id: customer.external_id,
          code:,
          timestamp: boundaries[:from_datetime] + 1.hour,
          properties: {
            billable_metric.field_name => 2,
            :agent_name => 'frodo'
          }
        ),
        Clickhouse::EventsRaw.create!(
          organization_id: organization.id,
          external_subscription_id: subscription.external_id,
          external_customer_id: customer.external_id,
          code:,
          timestamp: boundaries[:from_datetime] + 1.day,
          properties: {
            billable_metric.field_name => 2,
            :agent_name => 'aragorn'
          }
        ),
        Clickhouse::EventsRaw.create!(
          organization_id: organization.id,
          external_subscription_id: subscription.external_id,
          external_customer_id: customer.external_id,
          code:,
          timestamp: boundaries[:from_datetime] + 2.days,
          properties: {
            billable_metric.field_name => 2,
            :agent_name => 'aragorn',
            :operation_type => 'remove'
          }
        ),
        Clickhouse::EventsRaw.create!(
          organization_id: organization.id,
          external_subscription_id: subscription.external_id,
          external_customer_id: customer.external_id,
          code:,
          timestamp: boundaries[:from_datetime] + 2.days,
          properties: {billable_metric.field_name => 2}
        )
      ]
    end

    before do
      event_store.aggregation_property = billable_metric.field_name
    end

    it 'returns the unique count of event properties' do
      result = event_store.grouped_unique_count

      expect(result.count).to eq(3)

      null_group = result.find { |v| v[:groups]['agent_name'].nil? }
      expect(null_group[:groups]['other']).to be_nil
      expect(null_group[:value]).to eq(1)

      expect((result - [null_group]).map { |r| r[:value] }).to contain_exactly(1, 0)
    end

    context 'with no events' do
      let(:events) { [] }

      it 'returns the unique count of event properties' do
        result = event_store.grouped_unique_count
        expect(result.count).to eq(0)
      end
    end
  end

  describe '#grouped_prorated_unique_count' do
    let(:grouped_by) { %w[agent_name other] }
    let(:started_at) { Time.zone.parse('2023-03-01') }

    let(:events) do
      [
        Clickhouse::EventsRaw.create!(
          organization_id: organization.id,
          external_subscription_id: subscription.external_id,
          external_customer_id: customer.external_id,
          code:,
          timestamp: boundaries[:from_datetime] + 1.day,
          properties: {
            billable_metric.field_name => 2,
            :agent_name => 'frodo'
          }
        ),
        Clickhouse::EventsRaw.create!(
          organization_id: organization.id,
          external_subscription_id: subscription.external_id,
          external_customer_id: customer.external_id,
          code:,
          timestamp: boundaries[:from_datetime] + 1.day,
          properties: {
            billable_metric.field_name => 2,
            :agent_name => 'aragorn'
          }
        ),
        Clickhouse::EventsRaw.create!(
          organization_id: organization.id,
          external_subscription_id: subscription.external_id,
          external_customer_id: customer.external_id,
          code:,
          timestamp: (boundaries[:from_datetime] + 1.day).end_of_day,
          properties: {
            billable_metric.field_name => 2,
            :agent_name => 'aragorn',
            :operation_type => 'remove'
          }
        ),
        Clickhouse::EventsRaw.create!(
          organization_id: organization.id,
          external_subscription_id: subscription.external_id,
          external_customer_id: customer.external_id,
          code:,
          timestamp: boundaries[:from_datetime] + 2.days,
          properties: {billable_metric.field_name => 2}
        )
      ]
    end

    before do
      event_store.aggregation_property = billable_metric.field_name
    end

    it 'returns the unique count of event properties' do
      result = event_store.grouped_prorated_unique_count

      expect(result.count).to eq(3)

      null_group = result.find { |v| v[:groups]['agent_name'].nil? }
      expect(null_group[:groups]['other']).to be_nil
      expect(null_group[:value].round(3)).to eq(0.935) # 29/31

      # NOTE: Events calculation: [1/31, 30/31]
      expect((result - [null_group]).map { |r| r[:value].round(3) }).to contain_exactly(0.032, 0.968)
    end

    context 'with no events' do
      let(:events) { [] }

      it 'returns the unique count of event properties' do
        result = event_store.grouped_prorated_unique_count
        expect(result.count).to eq(0)
      end
    end
  end

  describe '#prorated_unique_count_breakdown' do
    it 'returns the breakdown of add and remove of unique event properties' do
      Clickhouse::EventsRaw.create!(
        transaction_id: SecureRandom.uuid,
        organization_id: organization.id,
        external_subscription_id: subscription.external_id,
        external_customer_id: customer.external_id,
        code:,
        timestamp: boundaries[:from_datetime] + 1.day,
        properties: {
          billable_metric.field_name => 2
        }
      )

      Clickhouse::EventsRaw.create!(
        transaction_id: SecureRandom.uuid,
        organization_id: organization.id,
        external_subscription_id: subscription.external_id,
        external_customer_id: customer.external_id,
        code:,
        timestamp: (boundaries[:from_datetime] + 1.day).end_of_day,
        properties: {
          billable_metric.field_name => 2,
          :operation_type => 'remove'
        }
      )

      event_store.aggregation_property = billable_metric.field_name

      result = event_store.prorated_unique_count_breakdown
      expect(result.count).to eq(6)

      grouped_result = result.group_by { |r| r['property'] }

      # NOTE: group with property 1
      group = grouped_result['1']
      expect(group.count).to eq(1)
      expect(group.first['prorated_value'].round(3)).to eq(0.516) # 16/31
      expect(group.first['operation_type']).to eq('add')

      # NOTE: group with property 2 (added and removed)
      group = grouped_result['2']
      expect(group.first['prorated_value'].round(3)).to eq(0.032) # 1/31
      expect(group.last['prorated_value'].round(3)).to eq(0.484) # 15/31
      expect(group.count).to eq(2)

      # NOTE: group with property 3
      group = grouped_result['3']
      expect(group.count).to eq(1)
      expect(group.first['prorated_value'].round(3)).to eq(0.452) # 14/31
      expect(group.first['operation_type']).to eq('add')

      # NOTE: group with property 4
      group = grouped_result['4']
      expect(group.count).to eq(1)
      expect(group.first['prorated_value'].round(3)).to eq(0.419) # 13/31
      expect(group.first['operation_type']).to eq('add')

      # NOTE: group with property 5
      group = grouped_result['5']
      expect(group.count).to eq(1)
      expect(group.first['prorated_value'].round(3)).to eq(0.387) # 12/31
      expect(group.first['operation_type']).to eq('add')
    end
  end

  describe '.events_values' do
    it 'returns the value attached to each event' do
      event_store.aggregation_property = billable_metric.field_name
      event_store.numeric_property = true

      expect(event_store.events_values).to eq([1, 2, 3, 4, 5])
    end

    context 'when exclude_event is true' do
      subject(:event_store) do
        described_class.new(
          code:,
          subscription:,
          boundaries:,
          filters: {
            grouped_by:,
            grouped_by_values:,
            matching_filters:,
            ignored_filters:,
            event:
          }
        )
      end

      let(:event) do
        Clickhouse::EventsRaw.create!(
          transaction_id: SecureRandom.uuid,
          organization_id: organization.id,
          external_subscription_id: subscription.external_id,
          external_customer_id: customer.external_id,
          code:,
          timestamp: boundaries[:from_datetime] + 1.day,
          properties: {billable_metric.field_name => 6}
        )
      end

      it 'excludes current event but returns the value attached to other events' do
        event
        event_store.aggregation_property = billable_metric.field_name
        event_store.numeric_property = true

        expect(event_store.events_values(exclude_event: true)).to eq([1, 2, 3, 4, 5])
      end
    end
  end

  describe '.last_event' do
    it 'returns the last event' do
      event_store.aggregation_property = billable_metric.field_name
      event_store.numeric_property = true

      expect(event_store.last_event.transaction_id).to eq(events.last.transaction_id)
    end
  end

  describe '.grouped_last_event' do
    let(:grouped_by) { %w[cloud] }

    before do
      event_store.aggregation_property = billable_metric.field_name
      event_store.numeric_property = true
    end

    it 'returns the last events grouped by the provided group' do
      result = event_store.grouped_last_event

      expect(result.count).to eq(4)

      null_group = result.find { |v| v[:groups]['cloud'].nil? }
      expect(null_group[:groups]['cloud']).to be_nil
      expect(null_group[:value]).to eq(4)
      expect(null_group[:timestamp]).not_to be_nil

      (result - [null_group]).each do |row|
        expect(row[:groups]['cloud']).not_to be_nil
        expect(row[:value]).not_to be_nil
        expect(row[:timestamp]).not_to be_nil
      end
    end

    context 'with multiple groups' do
      let(:grouped_by) { %w[cloud region] }

      it 'returns the last events grouped by the provided groups' do
        result = event_store.grouped_last_event

        expect(result.count).to eq(4)

        null_group = result.find { |v| v[:groups]['cloud'].nil? }
        expect(null_group[:groups]['cloud']).to be_nil
        expect(null_group[:groups]['region']).to be_nil
        expect(null_group[:value]).to eq(4)
        expect(null_group[:timestamp]).not_to be_nil

        (result - [null_group]).each do |row|
          expect(row[:groups]['cloud']).not_to be_nil
          expect(row[:groups]['region']).not_to be_nil
          expect(row[:value]).not_to be_nil
          expect(row[:timestamp]).not_to be_nil
        end
      end
    end
  end

  describe '.prorated_events_values' do
    it 'returns the values attached to each event with prorata on period duration' do
      event_store.aggregation_property = billable_metric.field_name
      event_store.numeric_property = true

      expect(event_store.prorated_events_values(31).map { |v| v.round(3) }).to eq(
        [0.516, 0.968, 1.355, 1.677, 1.935]
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

      null_group = result.find { |v| v[:groups]['cloud'].nil? }
      expect(null_group[:value]).to eq(4)

      result[...-1].each do |row|
        next if row[:groups]['cloud'].nil?

        expect(row[:groups]['cloud']).not_to be_nil
        expect(row[:value]).not_to be_nil
      end
    end

    context 'with multiple groups' do
      let(:grouped_by) { %w[cloud region] }

      it 'returns the max values grouped by the provided groups' do
        result = event_store.grouped_max

        expect(result.count).to eq(4)

        null_group = result.find { |v| v[:groups]['cloud'].nil? }
        expect(null_group[:groups]['region']).to be_nil
        expect(null_group[:value]).to eq(4)

        result[...-1].each do |row|
          next if row[:groups]['cloud'].nil?

          expect(row[:groups]['cloud']).not_to be_nil
          expect(row[:groups]['region']).not_to be_nil
          expect(row[:value]).not_to be_nil
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

    it 'returns the value attached to each event prorated on the provided duration' do
      result = event_store.grouped_last

      expect(result.count).to eq(4)

      null_group = result.find { |v| v[:groups]['cloud'].nil? }
      expect(null_group[:value]).to eq(4)

      result[...-1].each do |row|
        next if row[:groups]['cloud'].nil?

        expect(row[:groups]['cloud']).not_to be_nil
        expect(row[:value]).not_to be_nil
      end
    end

    context 'with multiple groups' do
      let(:grouped_by) { %w[cloud region] }

      it 'returns the last value for each provided groups' do
        result = event_store.grouped_last

        expect(result.count).to eq(4)

        null_group = result.find { |v| v[:groups]['cloud'].nil? }
        expect(null_group[:groups]['region']).to be_nil
        expect(null_group[:value]).to eq(4)

        result[...-1].each do |row|
          next if row[:groups]['cloud'].nil?

          expect(row[:groups]['cloud']).not_to be_nil
          expect(row[:groups]['region']).not_to be_nil
          expect(row[:value]).not_to be_nil
        end
      end
    end
  end

  describe '.sum' do
    it 'returns the sum of event properties' do
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

      null_group = result.find { |v| v[:groups]['cloud'].nil? }
      expect(null_group[:value]).to eq(6)

      result[...-1].each do |row|
        next if row[:groups]['cloud'].nil?

        expect(row[:groups]['cloud']).not_to be_nil
        expect(row[:value]).not_to be_nil
      end
    end

    context 'with multiple groups' do
      let(:grouped_by) { %w[cloud region] }

      it 'returns the sum of values grouped by the provided groups' do
        result = event_store.grouped_sum

        expect(result.count).to eq(4)

        null_group = result.find { |v| v[:groups]['cloud'].nil? }
        expect(null_group[:groups]['region']).to be_nil
        expect(null_group[:value]).to eq(6)

        result[...-1].each do |row|
          next if row[:groups]['cloud'].nil?

          expect(row[:groups]['cloud']).not_to be_nil
          expect(row[:groups]['region']).not_to be_nil
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

  describe '.grouped_prorated_sum' do
    let(:grouped_by) { %w[cloud] }

    it 'returns the prorated sum of event properties' do
      event_store.aggregation_property = billable_metric.field_name
      event_store.numeric_property = true

      result = event_store.grouped_prorated_sum(period_duration: 31)

      expect(result.count).to eq(4)

      null_group = result.find { |v| v[:groups]['cloud'].nil? }
      expect(null_group[:groups]['cloud']).to be_nil
      expect(null_group[:value].round(5)).to eq(2.64516)

      (result - [null_group]).each do |row|
        expect(row[:groups]['cloud']).not_to be_nil
        expect(row[:value]).not_to be_nil
      end
    end

    context 'with persisted_duration' do
      it 'returns the prorated sum of event properties' do
        event_store.aggregation_property = billable_metric.field_name
        event_store.numeric_property = true

        result = event_store.grouped_prorated_sum(period_duration: 31, persisted_duration: 10)

        expect(result.count).to eq(4)

        null_group = result.find { |v| v[:groups]['cloud'].nil? }
        expect(null_group[:groups]['cloud']).to be_nil
        expect(null_group[:value].round(5)).to eq(1.93548)

        (result - [null_group]).each do |row|
          expect(row[:groups]['cloud']).not_to be_nil
          expect(row[:value]).not_to be_nil
        end
      end
    end

    context 'with multiple groups' do
      let(:grouped_by) { %w[cloud region] }

      it 'returns the sum of values grouped by the provided groups' do
        event_store.aggregation_property = billable_metric.field_name
        event_store.numeric_property = true

        result = event_store.grouped_prorated_sum(period_duration: 31)

        expect(result.count).to eq(4)

        null_group = result.find { |v| v[:groups]['cloud'].nil? }
        expect(null_group[:groups]['cloud']).to be_nil
        expect(null_group[:groups]['region']).to be_nil
        expect(null_group[:value].round(5)).to eq(2.64516)

        (result - [null_group]).each do |row|
          expect(row[:groups]['cloud']).not_to be_nil
          expect(row[:groups]['region']).not_to be_nil
          expect(row[:value]).not_to be_nil
        end
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
            value: e.properties[billable_metric.field_name].to_f
          }
        end
      )
    end
  end

  describe '.weighted_sum' do
    let(:started_at) { Time.zone.parse('2023-03-01') }

    let(:events_values) do
      [
        {timestamp: Time.zone.parse('2023-03-01 00:00:00.000'), value: 2},
        {timestamp: Time.zone.parse('2023-03-01 01:00:00'), value: 3},
        {timestamp: Time.zone.parse('2023-03-01 01:30:00'), value: 1},
        {timestamp: Time.zone.parse('2023-03-01 02:00:00'), value: -4},
        {timestamp: Time.zone.parse('2023-03-01 04:00:00'), value: -2},
        {timestamp: Time.zone.parse('2023-03-01 05:00:00'), value: 10},
        {timestamp: Time.zone.parse('2023-03-01 05:30:00'), value: -10}
      ]
    end

    let(:events) do
      events_values.map do |values|
        properties = {value: values[:value]}
        properties[:region] = values[:region] if values[:region]

        Clickhouse::EventsRaw.create!(
          transaction_id: SecureRandom.uuid,
          organization_id: organization.id,
          external_subscription_id: subscription.external_id,
          external_customer_id: customer.external_id,
          code:,
          timestamp: values[:timestamp],
          properties:
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
          {timestamp: Time.zone.parse('2023-03-01 00:00:00.000'), value: 1000}
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
          {timestamp: Time.zone.parse('2023-03-01 00:00:00.000'), value: 3},
          {timestamp: Time.zone.parse('2023-03-01 00:00:00.000'), value: 3}
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

    context 'with filters' do
      let(:matching_filters) { {region: ['europe']} }

      let(:events_values) do
        [
          {timestamp: Time.zone.parse('2023-03-01 00:00:00.000'), value: 1000, region: 'europe'}
        ]
      end

      it 'returns the weighted sum of event properties scoped to the group' do
        expect(event_store.weighted_sum.round(5)).to eq(1000.0)
      end
    end
  end

  describe '.grouped_weighted_sum' do
    let(:grouped_by) { %w[agent_name other] }

    let(:started_at) { Time.zone.parse('2023-03-01') }

    let(:events_values) do
      [
        {timestamp: Time.zone.parse('2023-03-01 00:00:00.000'), value: 2, agent_name: 'frodo'},
        {timestamp: Time.zone.parse('2023-03-01 01:00:00'), value: 3, agent_name: 'frodo'},
        {timestamp: Time.zone.parse('2023-03-01 01:30:00'), value: 1, agent_name: 'frodo'},
        {timestamp: Time.zone.parse('2023-03-01 02:00:00'), value: -4, agent_name: 'frodo'},
        {timestamp: Time.zone.parse('2023-03-01 04:00:00'), value: -2, agent_name: 'frodo'},
        {timestamp: Time.zone.parse('2023-03-01 05:00:00'), value: 10, agent_name: 'frodo'},
        {timestamp: Time.zone.parse('2023-03-01 05:30:00'), value: -10, agent_name: 'frodo'},

        {timestamp: Time.zone.parse('2023-03-01 00:00:00.000'), value: 2, agent_name: 'aragorn'},
        {timestamp: Time.zone.parse('2023-03-01 01:00:00'), value: 3, agent_name: 'aragorn'},
        {timestamp: Time.zone.parse('2023-03-01 01:30:00'), value: 1, agent_name: 'aragorn'},
        {timestamp: Time.zone.parse('2023-03-01 02:00:00'), value: -4, agent_name: 'aragorn'},
        {timestamp: Time.zone.parse('2023-03-01 04:00:00'), value: -2, agent_name: 'aragorn'},
        {timestamp: Time.zone.parse('2023-03-01 05:00:00'), value: 10, agent_name: 'aragorn'},
        {timestamp: Time.zone.parse('2023-03-01 05:30:00'), value: -10, agent_name: 'aragorn'},

        {timestamp: Time.zone.parse('2023-03-01 00:00:00.000'), value: 2},
        {timestamp: Time.zone.parse('2023-03-01 01:00:00'), value: 3},
        {timestamp: Time.zone.parse('2023-03-01 01:30:00'), value: 1},
        {timestamp: Time.zone.parse('2023-03-01 02:00:00'), value: -4},
        {timestamp: Time.zone.parse('2023-03-01 04:00:00'), value: -2},
        {timestamp: Time.zone.parse('2023-03-01 05:00:00'), value: 10},
        {timestamp: Time.zone.parse('2023-03-01 05:30:00'), value: -10}
      ]
    end

    let(:events) do
      events_values.map do |values|
        properties = {value: values[:value]}
        properties[:region] = values[:region] if values[:region]
        properties[:agent_name] = values[:agent_name] if values[:agent_name]

        Clickhouse::EventsRaw.create!(
          transaction_id: SecureRandom.uuid,
          organization_id: organization.id,
          external_subscription_id: subscription.external_id,
          external_customer_id: customer.external_id,
          code:,
          timestamp: values[:timestamp],
          properties:
        )
      end
    end

    before do
      event_store.aggregation_property = billable_metric.field_name
      event_store.numeric_property = true
    end

    it 'returns the weighted sum of event properties' do
      result = event_store.grouped_weighted_sum

      expect(result.count).to eq(3)

      null_group = result.find { |v| v[:groups]['agent_name'].nil? }
      expect(null_group[:groups]['agent_name']).to be_nil
      expect(null_group[:groups]['other']).to be_nil
      expect(null_group[:value].round(5)).to eq(0.02218)

      (result - [null_group]).each do |row|
        expect(row[:groups]['agent_name']).not_to be_nil
        expect(row[:groups]['other']).to be_nil
        expect(row[:value].round(5)).to eq(0.02218)
      end
    end

    context 'with no events' do
      let(:events_values) { [] }

      it 'returns the weighted sum of event properties' do
        result = event_store.grouped_weighted_sum

        expect(result.count).to eq(0)
      end
    end

    context 'with initial values' do
      let(:initial_values) do
        [
          {groups: {'agent_name' => 'frodo', 'other' => nil}, value: 1000},
          {groups: {'agent_name' => 'aragorn', 'other' => nil}, value: 1000},
          {groups: {'agent_name' => nil, 'other' => nil}, value: 1000}
        ]
      end

      it 'uses the initial value in the aggregation' do
        result = event_store.grouped_weighted_sum(initial_values:)

        expect(result.count).to eq(3)

        null_group = result.find { |v| v[:groups]['agent_name'].nil? }
        expect(null_group[:groups]['agent_name']).to be_nil
        expect(null_group[:groups]['other']).to be_nil
        expect(null_group[:value].round(5)).to eq(1000.02218)

        (result - [null_group]).each do |row|
          expect(row[:groups]['agent_name']).not_to be_nil
          expect(row[:groups]['other']).to be_nil
          expect(row[:value].round(5)).to eq(1000.02218)
        end
      end

      context 'without events' do
        let(:events_values) { [] }

        it 'uses only the initial value in the aggregation' do
          result = event_store.grouped_weighted_sum(initial_values:)

          expect(result.count).to eq(3)

          null_group = result.find { |v| v[:groups]['agent_name'].nil? }
          expect(null_group[:groups]['agent_name']).to be_nil
          expect(null_group[:groups]['other']).to be_nil
          expect(null_group[:value].round(5)).to eq(1000)

          (result - [null_group]).each do |row|
            expect(row[:groups]['agent_name']).not_to be_nil
            expect(row[:groups]['other']).to be_nil
            expect(row[:value].round(5)).to eq(1000)
          end
        end
      end
    end
  end
end
