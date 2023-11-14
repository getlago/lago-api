# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Charges::ApplyPayInAdvanceChargeModelService, type: :service do
  let(:charge_service) { described_class.new(charge:, aggregation_result:, properties:) }

  let(:charge) { create(:standard_charge, :pay_in_advance) }
  let(:aggregation_result) do
    BaseService::Result.new.tap do |result|
      result.aggregation = 10
      result.pay_in_advance_aggregation = 1
      result.count = 5
      result.options = {}
      result.aggregator = aggregator
    end
  end
  let(:properties) { {} }

  let(:aggregator) do
    BillableMetrics::Aggregations::CountService.new(
      event_store_class: Events::Stores::PostgresStore,
      charge:,
      subscription: nil,
      boundaries: nil,
    )
  end

  describe '#call' do
    context 'when charge is not pay_in_advance' do
      let(:charge) { create(:standard_charge) }

      it 'returns an error' do
        result = charge_service.call

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ServiceFailure)
          expect(result.error.code).to eq('apply_charge_model_error')
          expect(result.error.error_message).to eq('Charge is not pay_in_advance')
        end
      end
    end

    shared_examples 'a charge model' do
      it 'delegates to the standard charge model service' do
        previous_agg_result = BaseService::Result.new.tap do |result|
          result.aggregation = 9
          result.count = 4
          result.options = {}
          result.aggregator = aggregator
        end

        allow(charge_model_class).to receive(:apply)
          .with(charge:, aggregation_result:, properties:)
          .and_return(BaseService::Result.new.tap { |r| r.amount = 10 })

        allow(charge_model_class).to receive(:apply)
          .with(charge:, aggregation_result: previous_agg_result, properties: properties.merge(ignore_last_event: true))
          .and_return(BaseService::Result.new.tap { |r| r.amount = 8 })

        result = charge_service.call

        expect(result.units).to eq(1)
        expect(result.count).to eq(1)
        expect(result.amount).to eq(200)
      end
    end

    describe 'when standard charge model' do
      let(:charge_model_class) { Charges::ChargeModels::StandardService }

      it_behaves_like 'a charge model'
    end

    describe 'when graduated charge model' do
      let(:charge) do
        create(
          :graduated_charge,
          :pay_in_advance,
          properties: {
            graduated_ranges: [
              {
                from_value: 0,
                to_value: nil,
                per_unit_amount: '0.01',
                flat_amount: '0.01',
              },
            ],
          },
        )
      end
      let(:charge_model_class) { Charges::ChargeModels::GraduatedService }

      it_behaves_like 'a charge model'
    end

    describe 'when package charge model' do
      let(:charge) { create(:package_charge, :pay_in_advance) }
      let(:charge_model_class) { Charges::ChargeModels::PackageService }

      it_behaves_like 'a charge model'
    end

    describe 'when percentage charge model' do
      let(:charge) { create(:percentage_charge, :pay_in_advance) }
      let(:charge_model_class) { Charges::ChargeModels::PercentageService }

      it_behaves_like 'a charge model'
    end

    describe 'when graduated percentage charge model' do
      let(:charge) do
        create(
          :graduated_percentage_charge,
          :pay_in_advance,
          properties: {
            graduated_percentage_ranges: [
              {
                from_value: 0,
                to_value: nil,
                flat_amount: '0.01',
                rate: '2',
              },
            ],
          },
        )
      end

      let(:charge_model_class) { Charges::ChargeModels::GraduatedPercentageService }

      it_behaves_like 'a charge model'
    end
  end
end
