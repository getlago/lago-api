# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Charges::Validators::PercentageService, type: :service do
  subject(:percentage_service) { described_class.new(charge: charge) }

  let(:charge) { build(:percentage_charge, properties: percentage_properties) }

  let(:percentage_properties) do
    {
      rate: '0.25',
      fixed_amount: '2',
    }
  end

  describe 'validate' do
    it { expect(percentage_service.validate).to be_success }

    context 'without rate' do
      let(:percentage_properties) do
        {
          fixed_amount: '2',
        }
      end

      it { expect(percentage_service.validate.error).to include(:invalid_rate) }
    end

    context 'when given rate is not string' do
      let(:percentage_properties) do
        {
          rate: 0.25,
          fixed_amount: '2',
        }
      end

      it { expect(percentage_service.validate.error).to include(:invalid_rate) }
    end

    context 'when rate cannot be converted to numeric format' do
      let(:percentage_properties) do
        {
          rate: 'bla',
          fixed_amount: '2',
        }
      end

      it { expect(percentage_service.validate.error).to include(:invalid_rate) }
    end

    context 'with negative rate' do
      let(:percentage_properties) do
        {
          rate: '-0.50',
          fixed_amount: '2',
        }
      end

      it { expect(percentage_service.validate.error).to include(:invalid_rate) }
    end

    context 'when rate is zero' do
      let(:percentage_properties) do
        {
          rate: '0.00',
          fixed_amount: '2',
        }
      end

      it { expect(percentage_service.validate.error).to include(:invalid_rate) }
    end

    context 'when free_units_per_events is not an integer' do
      let(:percentage_properties) do
        {
          rate: '0.25',
          free_units_per_events: 'foo',
        }
      end

      it { expect(percentage_service.validate.error).to include(:invalid_free_units_per_events) }
    end

    context 'when free_units_per_events is negative amount' do
      let(:percentage_properties) do
        {
          rate: '0.25',
          free_units_per_events: -1,
        }
      end

      it { expect(percentage_service.validate.error).to include(:invalid_free_units_per_events) }
    end

    context 'when fixed amount and free_units_per_total_aggregation cannot be converted to numeric' do
      let(:percentage_properties) do
        {
          rate: '0.25',
          fixed_amount: 'bla',
          free_units_per_total_aggregation: 'bla',
        }
      end

      it 'returns invalid amounts error' do
        expect(percentage_service.validate.error).to include(
          :invalid_fixed_amount,
          :invalid_free_units_per_total_aggregation,
        )
      end
    end

    context 'when given fixed amount and free_units_per_total_aggregation are not string' do
      let(:percentage_properties) do
        {
          rate: '0.25',
          fixed_amount: 2,
          free_units_per_total_aggregation: 1,
        }
      end

      it 'returns invalid amounts error' do
        expect(percentage_service.validate.error).to include(
          :invalid_fixed_amount,
          :invalid_free_units_per_total_aggregation,
        )
      end
    end

    context 'when given fixed amount is not string' do
      let(:percentage_properties) do
        {
          rate: '0.25',
          fixed_amount: 2,
        }
      end

      it { expect(percentage_service.validate.error).to include(:invalid_fixed_amount) }
    end

    context 'with negative fixed amount, free_units_per_events and free_units_per_total_aggregation' do
      let(:percentage_properties) do
        {
          rate: '0.25',
          fixed_amount: '-2',
          free_units_per_events: '-1',
          free_units_per_total_aggregation: '-1',
        }
      end

      it 'returns invalid amounts error' do
        expect(percentage_service.validate.error).to include(
          :invalid_fixed_amount,
          :invalid_free_units_per_events,
          :invalid_free_units_per_total_aggregation,
        )
      end
    end

    context 'without fixed_amount, free_units_per_events and free_units_per_total_aggregation' do
      let(:percentage_properties) do
        {
          rate: '0.25'
        }
      end

      it { expect(percentage_service.validate.error).to be nil }
    end
  end
end
