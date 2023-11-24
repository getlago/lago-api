# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Charges::ChargeModels::GraduatedService, type: :service do
  subject(:apply_graduated_service) do
    described_class.apply(
      charge:,
      aggregation_result:,
      properties: charge.properties,
    )
  end

  before do
    aggregation_result.aggregation = aggregation
  end

  let(:aggregation_result) { BaseService::Result.new }

  let(:charge) do
    create(
      :graduated_charge,
      properties: {
        graduated_ranges: [
          {
            from_value: 0,
            to_value: 10,
            per_unit_amount: '10',
            flat_amount: '2',
          },
          {
            from_value: 11,
            to_value: 20,
            per_unit_amount: '5',
            flat_amount: '3',
          },
          {
            from_value: 21,
            to_value: nil,
            per_unit_amount: '5',
            flat_amount: '3',
          },
        ],
      },
    )
  end

  context 'when aggregation is 0' do
    let(:aggregation) { 0 }

    it 'returns expected amount', :aggregate_failures do
      expect(apply_graduated_service.amount).to eq(0)
      expect(apply_graduated_service.unit_amount).to eq(0)
      expect(apply_graduated_service.amount_details).to eq(
        {
          graduated_ranges: [
            {
              flat_unit_amount: 0,
              from_value: 0,
              to_value: 10,
              per_unit_total_amount: 0,
              total_with_flat_amount: 0,
              per_unit_amount: 0,
              units: '0.0',
            },
          ],
        },
      )
    end
  end

  context 'when aggregation is 1' do
    let(:aggregation) { 1 }

    it 'returns expected amount', :aggregate_failures do
      expect(apply_graduated_service.amount).to eq(12)
      expect(apply_graduated_service.unit_amount).to eq(12)
      expect(apply_graduated_service.amount_details).to eq(
        {
          graduated_ranges: [
            {
              flat_unit_amount: 2,
              from_value: 0,
              to_value: 10,
              per_unit_total_amount: 10,
              total_with_flat_amount: 12,
              per_unit_amount: 10,
              units: '1.0',
            },
          ],
        },
      )
    end
  end

  context 'when aggregation is 10' do
    let(:aggregation) { 10 }

    it 'returns expected amount', :aggregate_failures do
      expect(apply_graduated_service.amount).to eq(102)
      expect(apply_graduated_service.unit_amount).to eq(10.2)
      expect(apply_graduated_service.amount_details).to eq(
        {
          graduated_ranges: [
            {
              flat_unit_amount: 2,
              from_value: 0,
              to_value: 10,
              per_unit_total_amount: 100,
              total_with_flat_amount: 102,
              per_unit_amount: 10,
              units: '10.0',
            },
          ],
        },
      )
    end
  end

  context 'when aggregation is 11' do
    let(:aggregation) { 11 }

    it 'returns expected amount', :aggregate_failures do
      expect(apply_graduated_service.amount).to eq(110)
      expect(apply_graduated_service.unit_amount).to eq(10)
      expect(apply_graduated_service.amount_details).to eq(
        {
          graduated_ranges: [
            {
              flat_unit_amount: 2,
              from_value: 0,
              to_value: 10,
              per_unit_total_amount: 100,
              total_with_flat_amount: 102,
              per_unit_amount: 10,
              units: '10.0',
            },
            {
              flat_unit_amount: 3,
              from_value: 11,
              to_value: 20,
              per_unit_total_amount: 5,
              total_with_flat_amount: 8,
              per_unit_amount: 5,
              units: '1.0',
            },
          ],
        },
      )
    end
  end

  context 'when aggregation is 12' do
    let(:aggregation) { 12 }

    it 'returns expected amount', :aggregate_failures do
      expect(apply_graduated_service.amount).to eq(115)
      expect(apply_graduated_service.unit_amount.round(5)).to eq(9.58333)
      expect(apply_graduated_service.amount_details).to eq(
        {
          graduated_ranges: [
            {
              flat_unit_amount: 2,
              from_value: 0,
              to_value: 10,
              per_unit_total_amount: 100,
              total_with_flat_amount: 102,
              per_unit_amount: 10,
              units: '10.0',
            },
            {
              flat_unit_amount: 3,
              from_value: 11,
              to_value: 20,
              per_unit_total_amount: 10,
              total_with_flat_amount: 13,
              per_unit_amount: 5,
              units: '2.0',
            },
          ],
        },
      )
    end
  end

  context 'when aggregation is 21' do
    let(:aggregation) { 21 }

    it 'returns expected amount', :aggregate_failures do
      expect(apply_graduated_service.amount).to eq(163)
      expect(apply_graduated_service.unit_amount.round(2)).to eq(7.76)
      expect(apply_graduated_service.amount_details).to eq(
        {
          graduated_ranges: [
            {
              flat_unit_amount: 2,
              from_value: 0,
              to_value: 10,
              per_unit_total_amount: 100,
              total_with_flat_amount: 102,
              per_unit_amount: 10,
              units: '10.0',
            },
            {
              flat_unit_amount: 3,
              from_value: 11,
              to_value: 20,
              per_unit_total_amount: 50,
              total_with_flat_amount: 53,
              per_unit_amount: 5,
              units: '10.0',
            },
            {
              flat_unit_amount: 3,
              from_value: 21,
              to_value: nil,
              per_unit_total_amount: 5,
              total_with_flat_amount: 8,
              per_unit_amount: 5,
              units: '1.0',
            },
          ],
        },
      )
    end
  end
end
