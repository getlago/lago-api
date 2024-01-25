# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Charges::ChargeModels::GroupedStandardService do
  subject(:apply_grouped_standard_service) do
    described_class.apply(
      charge:, aggregation_result:, properties: charge.properties,
    )
  end

  let(:aggregation_result) do
    BaseService::Result.new.tap do |result|
      result.aggregations = group_results.map do |group_result|
        BaseService::Result.new.tap do |aggregation|
          aggregation.aggregation = group_result[:aggregation]
          aggregation.count = group_result[:count]
          aggregation.grouped_by = group_result[:grouped_by]
        end
      end
    end
  end

  let(:group_results) do
    [
      {
        grouped_by: { 'cloud' => 'aws' },
        aggregation: 10,
        count: 2,
      },
      {
        grouped_by: { 'cloud' => 'gcp' },
        aggregation: 20,
        count: 7,
      },
    ]
  end

  let(:charge) do
    create(
      :standard_charge,
      charge_model: 'standard',
      properties: {
        amount: '5.12345',
      },
    )
  end

  it 'applies the charge model to the values' do
    expect(apply_grouped_standard_service.model_results.count).to eq(group_results.count)

    group_results.each_with_index do |group_result, index|
      result = apply_grouped_standard_service.model_results[index]

      expect(result.units).to eq(group_result[:aggregation])
      expect(result.current_usage_units).to eq(nil)
      expect(result.full_units_number).to eq(nil)
      expect(result.count).to eq(group_result[:count])
      expect(result.amount).to eq(group_result[:aggregation] * BigDecimal('5.12345'))
      expect(result.unit_amount).to eq(5.12345)
      expect(result.amount_details).to eq({})
      expect(result.grouped_by).to eq(group_result[:grouped_by])
    end
  end
end
