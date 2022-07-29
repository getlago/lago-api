# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BillableMetrics::Aggregations::CountService, type: :service do
  subject(:count_service) do
    described_class.new(billable_metric: billable_metric, subscription: subscription)
  end

  let(:subscription) { create(:subscription) }
  let(:organization) { subscription.organization }
  let(:customer) { subscription.customer }

  let(:billable_metric) do
    create(
      :billable_metric,
      organization: organization,
      aggregation_type: 'count_agg',
      billable_period: 'one_shot',
    )
  end

  let(:from_date) { Time.zone.today - 1.month }
  let(:to_date) { Time.zone.today }

  before do
    create_list(
      :event,
      4,
      code: billable_metric.code,
      subscription: subscription,
      customer: customer,
      timestamp: Time.zone.now,
    )
  end

  it 'aggregates the events' do
    result = count_service.aggregate(from_date: from_date, to_date: to_date)

    expect(result.aggregation).to eq(4)
  end

  context 'when events are out of bounds' do
    let(:to_date) { Time.zone.now - 2.days }

    it 'does not take events into account' do
      result = count_service.aggregate(from_date: from_date, to_date: to_date)

      expect(result.aggregation).to eq(0)
    end
  end
end
