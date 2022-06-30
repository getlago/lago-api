# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ::V1::BillableMetricSerializer do
  subject(:serializer) { described_class.new(billable_metric, root_name: 'billable_metric') }

  let(:billable_metric) { create(:billable_metric) }

  it 'serializes the object' do
    result = JSON.parse(serializer.to_json)

    aggregate_failures do
      expect(result['billable_metric']['lago_id']).to eq(billable_metric.id)
      expect(result['billable_metric']['name']).to eq(billable_metric.name)
      expect(result['billable_metric']['code']).to eq(billable_metric.code)
      expect(result['billable_metric']['description']).to eq(billable_metric.description)
      expect(result['billable_metric']['aggregation_type']).to eq(billable_metric.aggregation_type)
      expect(result['billable_metric']['field_name']).to eq(billable_metric.field_name)
      expect(result['billable_metric']['created_at']).to eq(billable_metric.created_at.iso8601)
    end
  end
end
