# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Charges::Validators::PercentageService, type: :service do
  subject(:percentage_service) { described_class.new(charge:) }

  let(:charge) { build(:percentage_charge, properties: percentage_properties) }

  let(:percentage_properties) do
    {
      rate: '0.25',
      fixed_amount: '2',
    }
  end

  describe '.valid?' do
    it { expect(percentage_service).to be_valid }

    context 'when billable metric is latest_agg' do
      let(:billable_metric) { create(:latest_billable_metric) }
      let(:charge) { build(:percentage_charge, properties: percentage_properties, billable_metric:) }
      let(:percentage_properties) do
        {
          rate: 0.25,
          fixed_amount: '2',
        }
      end

      it 'is invalid' do
        aggregate_failures do
          expect(percentage_service).not_to be_valid
          expect(percentage_service.result.error).to be_a(BaseService::ValidationFailure)
          expect(percentage_service.result.error.messages.keys).to include(:billable_metric)
          expect(percentage_service.result.error.messages[:billable_metric]).to include('invalid_value')
        end
      end
    end

    context 'without rate' do
      let(:percentage_properties) do
        {
          fixed_amount: '2',
        }
      end

      it 'is invalid' do
        aggregate_failures do
          expect(percentage_service).not_to be_valid
          expect(percentage_service.result.error).to be_a(BaseService::ValidationFailure)
          expect(percentage_service.result.error.messages.keys).to include(:rate)
          expect(percentage_service.result.error.messages[:rate]).to include('invalid_rate')
        end
      end
    end

    context 'when given rate is not string' do
      let(:percentage_properties) do
        {
          rate: 0.25,
          fixed_amount: '2',
        }
      end

      it 'is invalid' do
        aggregate_failures do
          expect(percentage_service).not_to be_valid
          expect(percentage_service.result.error).to be_a(BaseService::ValidationFailure)
          expect(percentage_service.result.error.messages.keys).to include(:rate)
          expect(percentage_service.result.error.messages[:rate]).to include('invalid_rate')
        end
      end
    end

    context 'when rate cannot be converted to numeric format' do
      let(:percentage_properties) do
        {
          rate: 'bla',
          fixed_amount: '2',
        }
      end

      it 'is invalid' do
        aggregate_failures do
          expect(percentage_service).not_to be_valid
          expect(percentage_service.result.error).to be_a(BaseService::ValidationFailure)
          expect(percentage_service.result.error.messages.keys).to include(:rate)
          expect(percentage_service.result.error.messages[:rate]).to include('invalid_rate')
        end
      end
    end

    context 'with negative rate' do
      let(:percentage_properties) do
        {
          rate: '-0.50',
          fixed_amount: '2',
        }
      end

      it 'is invalid' do
        aggregate_failures do
          expect(percentage_service).not_to be_valid
          expect(percentage_service.result.error).to be_a(BaseService::ValidationFailure)
          expect(percentage_service.result.error.messages.keys).to include(:rate)
          expect(percentage_service.result.error.messages[:rate]).to include('invalid_rate')
        end
      end
    end

    context 'when rate is zero' do
      let(:percentage_properties) do
        { rate: '0.00', fixed_amount: '2' }
      end

      it { expect(percentage_service).to be_valid }
    end

    context 'when free_units_per_events is not an integer' do
      let(:percentage_properties) do
        {
          rate: '0.25',
          free_units_per_events: 'foo',
        }
      end

      it 'is invalid' do
        aggregate_failures do
          expect(percentage_service).not_to be_valid
          expect(percentage_service.result.error).to be_a(BaseService::ValidationFailure)
          expect(percentage_service.result.error.messages.keys).to include(:free_units_per_events)
          expect(percentage_service.result.error.messages[:free_units_per_events])
            .to include('invalid_free_units_per_events')
        end
      end
    end

    context 'when free_units_per_events is negative amount' do
      let(:percentage_properties) do
        {
          rate: '0.25',
          free_units_per_events: -1,
        }
      end

      it 'is invalid' do
        aggregate_failures do
          expect(percentage_service).not_to be_valid
          expect(percentage_service.result.error).to be_a(BaseService::ValidationFailure)
          expect(percentage_service.result.error.messages.keys).to include(:free_units_per_events)
          expect(percentage_service.result.error.messages[:free_units_per_events])
            .to include('invalid_free_units_per_events')
        end
      end
    end

    context 'when fixed amount and free_units_per_total_aggregation cannot be converted to numeric' do
      let(:percentage_properties) do
        {
          rate: '0.25',
          fixed_amount: 'bla',
          free_units_per_total_aggregation: 'bla',
        }
      end

      it 'is invalid' do
        aggregate_failures do
          expect(percentage_service).not_to be_valid
          expect(percentage_service.result.error).to be_a(BaseService::ValidationFailure)
          expect(percentage_service.result.error.messages.keys).to eq(
            [
              :fixed_amount,
              :free_units_per_total_aggregation,
            ],
          )
          expect(percentage_service.result.error.messages[:fixed_amount])
            .to include('invalid_fixed_amount')
          expect(percentage_service.result.error.messages[:free_units_per_total_aggregation])
            .to include('invalid_free_units_per_total_aggregation')
        end
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

      it 'is invalid' do
        aggregate_failures do
          expect(percentage_service).not_to be_valid
          expect(percentage_service.result.error).to be_a(BaseService::ValidationFailure)
          expect(percentage_service.result.error.messages.keys).to eq(
            [
              :fixed_amount,
              :free_units_per_total_aggregation,
            ],
          )
          expect(percentage_service.result.error.messages[:fixed_amount])
            .to include('invalid_fixed_amount')
          expect(percentage_service.result.error.messages[:free_units_per_total_aggregation])
            .to include('invalid_free_units_per_total_aggregation')
        end
      end
    end

    context 'when given fixed amount is not string' do
      let(:percentage_properties) do
        {
          rate: '0.25',
          fixed_amount: 2,
        }
      end

      it 'is invalid' do
        aggregate_failures do
          expect(percentage_service).not_to be_valid
          expect(percentage_service.result.error).to be_a(BaseService::ValidationFailure)
          expect(percentage_service.result.error.messages.keys).to include(:fixed_amount)
          expect(percentage_service.result.error.messages[:fixed_amount]).to include('invalid_fixed_amount')
        end
      end
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

      it 'is invalid' do
        aggregate_failures do
          expect(percentage_service).not_to be_valid
          expect(percentage_service.result.error).to be_a(BaseService::ValidationFailure)
          expect(percentage_service.result.error.messages.keys).to eq(
            [
              :fixed_amount,
              :free_units_per_events,
              :free_units_per_total_aggregation,
            ],
          )
          expect(percentage_service.result.error.messages[:fixed_amount])
            .to include('invalid_fixed_amount')
          expect(percentage_service.result.error.messages[:free_units_per_events])
            .to include('invalid_free_units_per_events')
          expect(percentage_service.result.error.messages[:free_units_per_total_aggregation])
            .to include('invalid_free_units_per_total_aggregation')
        end
      end
    end

    context 'without fixed_amount, free_units_per_events and free_units_per_total_aggregation' do
      let(:percentage_properties) do
        {
          rate: '0.25',
        }
      end

      it { expect(percentage_service).to be_valid }
    end

    context 'with per_transaction_min_amount' do
      around { |test| lago_premium!(&test) }

      let(:percentage_properties) do
        {
          rate: '0.25',
          fixed_amount: '2',
          per_transaction_min_amount:,
        }
      end

      context 'when it is not a string' do
        let(:per_transaction_min_amount) { 2 }

        it 'is invalid' do
          aggregate_failures do
            expect(percentage_service).not_to be_valid
            expect(percentage_service.result.error).to be_a(BaseService::ValidationFailure)
            expect(percentage_service.result.error.messages.keys).to include(:per_transaction_min_amount)
            expect(percentage_service.result.error.messages[:per_transaction_min_amount])
              .to include('invalid_amount')
          end
        end
      end

      context 'when it is negative' do
        let(:per_transaction_min_amount) { '-3' }

        it 'is invalid' do
          aggregate_failures do
            expect(percentage_service).not_to be_valid
            expect(percentage_service.result.error).to be_a(BaseService::ValidationFailure)
            expect(percentage_service.result.error.messages.keys).to include(:per_transaction_min_amount)
            expect(percentage_service.result.error.messages[:per_transaction_min_amount])
              .to include('invalid_amount')
          end
        end
      end
    end

    context 'with per_transaction_max_amount' do
      around { |test| lago_premium!(&test) }

      let(:percentage_properties) do
        {
          rate: '0.25',
          fixed_amount: '2',
          per_transaction_max_amount:,
        }
      end

      context 'when it is not a string' do
        let(:per_transaction_max_amount) { 2 }

        it 'is invalid' do
          aggregate_failures do
            expect(percentage_service).not_to be_valid
            expect(percentage_service.result.error).to be_a(BaseService::ValidationFailure)
            expect(percentage_service.result.error.messages.keys).to include(:per_transaction_max_amount)
            expect(percentage_service.result.error.messages[:per_transaction_max_amount])
              .to include('invalid_amount')
          end
        end
      end

      context 'when it is negative' do
        let(:per_transaction_max_amount) { '-3' }

        it 'is invalid' do
          aggregate_failures do
            expect(percentage_service).not_to be_valid
            expect(percentage_service.result.error).to be_a(BaseService::ValidationFailure)
            expect(percentage_service.result.error.messages.keys).to include(:per_transaction_max_amount)
            expect(percentage_service.result.error.messages[:per_transaction_max_amount])
              .to include('invalid_amount')
          end
        end
      end
    end

    context 'with both per_transaction_min_amount and per_transaction_max_amount' do
      around { |test| lago_premium!(&test) }

      let(:percentage_properties) do
        {
          rate: '0.25',
          fixed_amount: '2',
          per_transaction_min_amount: '3',
          per_transaction_max_amount: '2',
        }
      end

      it 'ensures that max is higher than min' do
        aggregate_failures do
          expect(percentage_service).not_to be_valid
          expect(percentage_service.result.error).to be_a(BaseService::ValidationFailure)
          expect(percentage_service.result.error.messages.keys).to include(:per_transaction_max_amount)
          expect(percentage_service.result.error.messages[:per_transaction_max_amount])
            .to include('per_transaction_max_lower_than_per_transaction_min')
        end
      end
    end
  end
end
