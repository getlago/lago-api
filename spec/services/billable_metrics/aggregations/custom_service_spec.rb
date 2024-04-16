# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BillableMetrics::Aggregations::CustomService, type: :service do
  subject(:custom_service) do
    described_class.new(
      event_store_class:,
      charge:,
      subscription:,
      boundaries: {
        from_datetime:,
        to_datetime:,
      },
      filters:,
    )
  end

  let(:event_store_class) { Events::Stores::PostgresStore }
  let(:filters) { { group:, grouped_by: } }

  let(:subscription) { create(:subscription) }
  let(:organization) { subscription.organization }
  let(:customer) { subscription.customer }

  let(:group) { nil }
  let(:grouped_by) { nil }

  let(:billable_metric) do
    create(:custom_billable_metric, organization:)
  end

  let(:charge) { create(:standard_charge, billable_metric:) }

  let(:from_datetime) { (Time.current - 1.month).beginning_of_day }
  let(:to_datetime) { Time.current.end_of_day }

  it 'aggregates the events' do
    result = custom_service.aggregate

    expect(result.aggregation).to eq(0)
    expect(result.count).to eq(0)
  end
end
