# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Charges::ApplyInstantChargeModelService, type: :service do
  let(:charge_service) { described_class.new(charge:, aggregation_result:, properties:) }

  let(:charge) { create(:standard_charge, :instant) }
  let(:aggregation_result) do
    BaseService::Result.new.tap do |result|
      result.aggregation = 10
      result.instant_aggregation = 1
      result.count = 5
      result.options = {}
    end
  end
  let(:properties) { {} }

  describe '#call' do
    context 'when charge is not instant' do
      let(:charge) { create(:standard_charge) }

      it 'returns an error' do
        result = charge_service.call

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ServiceFailure)
          expect(result.error.code).to eq('apply_charge_model_error')
          expect(result.error.error_message).to eq('Charge is not instant')
        end
      end
    end

    shared_examples 'a charge model' do
      it 'delegates to the standard charge model service' do
        previous_agg_result = BaseService::Result.new.tap do |result|
          result.aggregation = 9
          result.count = 4
          result.options = {}
        end

        allow(charge_model_class).to receive(:apply)
          .with(charge:, aggregation_result:, properties:)
          .and_return(BaseService::Result.new.tap { |r| r.amount = 10 })

        allow(charge_model_class).to receive(:apply)
          .with(charge:, aggregation_result: previous_agg_result, properties:)
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
          :instant,
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
      let(:charge) { create(:package_charge, :instant) }
      let(:charge_model_class) { Charges::ChargeModels::PackageService }

      it_behaves_like 'a charge model'
    end

    describe 'when percentage charge model' do
      let(:charge) { create(:percentage_charge, :instant) }
      let(:charge_model_class) { Charges::ChargeModels::PercentageService }

      it_behaves_like 'a charge model'
    end
  end
end
