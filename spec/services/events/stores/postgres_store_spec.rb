# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Events::Stores::PostgresStore, type: :service, transaction: false do
  subject(:event_store) do
    described_class.new(
      code:,
      subscription:,
      boundaries:,
      group:,
      event:,
    )
  end

  let(:billable_metric) { create(:billable_metric, field_name: 'value') }
  let(:organization) { billable_metric.organization }

  let(:customer) { create(:customer, organization:) }
  let(:subscription) { create(:subscription, customer:, started_at: DateTime.parse('2023-03-15')) }

  let(:code) { billable_metric.code }

  let(:boundaries) do
    {
      from_datetime: subscription.started_at.beginning_of_day,
      to_datetime: subscription.started_at.end_of_month.end_of_day,
    }
  end

  let(:group) { nil }
  let(:event) { nil }

  let(:events_list) do
    3.times do |i|
      event = create(
        :event,
        organization:,
        code:,
        timestamp: boundaries[:from_datetime] + 3.days,
        external_subscription_id: subscription.external_id,
        external_customer_id: customer.external_id,
        properties: {
          billable_metric.field_name => (i + 0.34567).to_s,
        },
      )

      if group
        event.properties[group.key] = group.value
        event.save!
      end
    end
  end

  before { events_list }

  describe '.events' do
    it 'returns a list of events' do
      expect(event_store.events.map(&:id)).to match_array(
        Event.where(organization_id: organization.id).pluck(:id),
      )
    end

    context 'with group' do
      let(:group) { create(:group, billable_metric:) }

      it 'returns a list of events' do
        expect(event_store.events.map(&:id)).to match_array(
          Event.where(organization_id: organization.id).pluck(:id),
        )
      end
    end
  end

  describe '.count' do
    it 'returns the number of unique events' do
      expect(event_store.count).to eq(3)
    end
  end

  describe '.events_values' do
    before do
      event_store.numeric_property = true
      event_store.aggregation_property = billable_metric.field_name
    end

    it 'returns the value attached to each event' do
      expect(event_store.events_values).to match_array(
        [0.34567, 1.34567, 2.34567],
      )
    end
  end

  describe '.max' do
    before do
      event_store.numeric_property = true
      event_store.aggregation_property = billable_metric.field_name
    end

    it 'returns the max value' do
      expect(event_store.max).to eq(2.34567)
    end
  end
end
