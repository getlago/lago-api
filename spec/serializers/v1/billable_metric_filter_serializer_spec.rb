# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ::V1::BillableMetricFilterSerializer do
  subject(:serializer) { described_class.new(billable_metric_filter, root_name: 'billable_metric_filter') }

  let(:billable_metric_filter) { create(:billable_metric_filter) }
  let(:result) { JSON.parse(serializer.to_json) }

  it 'serializes the object' do
    aggregate_failures do
      expect(result['billable_metric_filter']).to include(
        'lago_id' => billable_metric_filter.id,
        'key' => billable_metric_filter.key,
        'values' => billable_metric_filter.values,
      )
    end
  end
end
