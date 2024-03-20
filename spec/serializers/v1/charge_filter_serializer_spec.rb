# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ::V1::ChargeFilterSerializer do
  subject(:serializer) { described_class.new(charge_filter, root_name: 'filter') }

  let(:charge_filter) { create(:charge_filter) }
  let(:filter) { create(:billable_metric_filter) }

  let(:filter_value) do
    create(
      :charge_filter_value,
      charge_filter:,
      billable_metric_filter: filter,
      values: [filter.values.first],
    )
  end

  before { filter_value }

  it 'serializes the object' do
    result = JSON.parse(serializer.to_json)

    aggregate_failures do
      expect(result['filter']['invoice_display_name']).to eq(charge_filter.invoice_display_name)
      expect(result['filter']['properties']).to eq(charge_filter.properties)
      expect(result['filter']['values']).to eq(
        {
          filter.key => filter_value.values,
        },
      )
    end
  end
end
