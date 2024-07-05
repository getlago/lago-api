# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Charge, type: :model do
  subject(:charge) { create(:standard_charge) }

  it_behaves_like 'paper_trail traceable'

  it { is_expected.to have_many(:filters).dependent(:destroy) }

  describe '#validate_graduated' do
    subject(:charge) do
      build(:graduated_charge, properties: charge_properties)
    end

    let(:charge_properties) do
      {graduated_ranges: [{'foo' => 'bar'}]}
    end
    let(:validation_service) { instance_double(Charges::Validators::GraduatedService) }

    let(:service_response) do
      BaseService::Result.new.validation_failure!(
        errors: {
          amount: ['invalid_amount'],
          ranges: ['invalid_graduated_ranges']
        }
      )
    end

    it 'delegates to a validation service' do
      allow(Charges::Validators::GraduatedService).to receive(:new)
        .and_return(validation_service)
      allow(validation_service).to receive(:valid?)
        .and_return(false)
      allow(validation_service).to receive(:result)
        .and_return(service_response)

      aggregate_failures do
        expect(charge).not_to be_valid
        expect(charge.errors.messages.keys).to include(:properties)
        expect(charge.errors.messages[:properties]).to include('invalid_amount')
        expect(charge.errors.messages[:properties]).to include('invalid_graduated_ranges')

        expect(Charges::Validators::GraduatedService).to have_received(:new).with(charge:)
        expect(validation_service).to have_received(:valid?)
        expect(validation_service).to have_received(:result)
      end
    end

    context 'when charge model is not graduated' do
      subject(:charge) { build(:standard_charge) }

      it 'does not apply the validation' do
        allow(Charges::Validators::GraduatedService).to receive(:new)
          .and_return(validation_service)
        allow(validation_service).to receive(:valid?)
          .and_return(false)
        allow(validation_service).to receive(:result)
          .and_return(service_response)

        charge.valid?

        expect(Charges::Validators::GraduatedService).not_to have_received(:new)
        expect(validation_service).not_to have_received(:valid?)
        expect(validation_service).not_to have_received(:result)
      end
    end
  end

  describe '#validate_amount' do
    subject(:charge) do
      build(:standard_charge, properties: charge_properties)
    end

    let(:charge_properties) { [{'foo' => 'bar'}] }
    let(:validation_service) { instance_double(Charges::Validators::StandardService) }

    let(:service_response) do
      BaseService::Result.new.validation_failure!(
        errors: {
          amount: ['invalid_amount']
        }
      )
    end

    it 'delegates to a validation service' do
      allow(Charges::Validators::StandardService).to receive(:new)
        .and_return(validation_service)
      allow(validation_service).to receive(:valid?)
        .and_return(false)
      allow(validation_service).to receive(:result)
        .and_return(service_response)

      aggregate_failures do
        expect(charge).not_to be_valid
        expect(charge.errors.messages.keys).to include(:properties)
        expect(charge.errors.messages[:properties]).to include('invalid_amount')

        expect(Charges::Validators::StandardService).to have_received(:new).with(charge:)
        expect(validation_service).to have_received(:valid?)
        expect(validation_service).to have_received(:result)
      end
    end

    context 'when charge model is not graduated' do
      subject(:charge) { build(:graduated_charge) }

      it 'does not apply the validation' do
        allow(Charges::Validators::StandardService).to receive(:new)
          .and_return(validation_service)
        allow(validation_service).to receive(:valid?)
          .and_return(false)
        allow(validation_service).to receive(:result)
          .and_return(service_response)

        charge.valid?

        expect(Charges::Validators::StandardService).not_to have_received(:new)
        expect(validation_service).not_to have_received(:valid?)
        expect(validation_service).not_to have_received(:result)
      end
    end
  end

  describe '#validate_package' do
    subject(:charge) do
      build(:package_charge, properties: charge_properties)
    end

    let(:charge_properties) { [{'foo' => 'bar'}] }
    let(:validation_service) { instance_double(Charges::Validators::PackageService) }

    let(:service_response) do
      BaseService::Result.new.validation_failure!(
        errors: {
          amount: ['invalid_amount'],
          free_units: ['invalid_free_units'],
          package_size: ['invalid_package_size']
        }
      )
    end

    it 'delegates to a validation service' do
      allow(Charges::Validators::PackageService).to receive(:new)
        .and_return(validation_service)
      allow(validation_service).to receive(:valid?)
        .and_return(false)
      allow(validation_service).to receive(:result)
        .and_return(service_response)

      aggregate_failures do
        expect(charge).not_to be_valid
        expect(charge.errors.messages.keys).to include(:properties)
        expect(charge.errors.messages[:properties]).to include('invalid_amount')
        expect(charge.errors.messages[:properties]).to include('invalid_free_units')
        expect(charge.errors.messages[:properties]).to include('invalid_package_size')

        expect(Charges::Validators::PackageService).to have_received(:new).with(charge:)
        expect(validation_service).to have_received(:valid?)
        expect(validation_service).to have_received(:result)
      end
    end

    context 'when charge model is not package' do
      subject(:charge) { build(:standard_charge) }

      it 'does not apply the validation' do
        allow(Charges::Validators::PackageService).to receive(:new)
          .and_return(validation_service)
        allow(validation_service).to receive(:valid?)
          .and_return(false)
        allow(validation_service).to receive(:result)
          .and_return(service_response)

        charge.valid?

        expect(Charges::Validators::PackageService).not_to have_received(:new)
        expect(validation_service).not_to have_received(:valid?)
        expect(validation_service).not_to have_received(:result)
      end
    end
  end

  describe '#validate_percentage' do
    subject(:charge) { build(:percentage_charge, properties: charge_properties) }

    let(:charge_properties) { [{'foo' => 'bar'}] }
    let(:validation_service) { instance_double(Charges::Validators::PercentageService) }

    let(:service_response) do
      BaseService::Result.new.validation_failure!(
        errors: {
          amount: ['invalid_fixed_amount'],
          free_units_per_events: ['invalid_free_units_per_events'],
          free_units_per_total_aggregation: ['invalid_free_units_per_total_aggregation'],
          rate: ['invalid_rate']
        }
      )
    end

    it 'delegates to a validation service' do
      allow(Charges::Validators::PercentageService).to receive(:new)
        .and_return(validation_service)
      allow(validation_service).to receive(:valid?)
        .and_return(false)
      allow(validation_service).to receive(:result)
        .and_return(service_response)

      aggregate_failures do
        expect(charge).not_to be_valid
        expect(charge.errors.messages.keys).to include(:properties)
        expect(charge.errors.messages[:properties]).to include('invalid_rate')
        expect(charge.errors.messages[:properties]).to include('invalid_fixed_amount')
        expect(charge.errors.messages[:properties]).to include('invalid_free_units_per_events')
        expect(charge.errors.messages[:properties]).to include('invalid_free_units_per_total_aggregation')

        expect(Charges::Validators::PercentageService).to have_received(:new).with(charge:)
        expect(validation_service).to have_received(:valid?)
        expect(validation_service).to have_received(:result)
      end
    end

    context 'when charge model is not percentage' do
      subject(:charge) { build(:standard_charge) }

      it 'does not apply the validation' do
        allow(Charges::Validators::PercentageService).to receive(:new)
          .and_return(validation_service)
        allow(validation_service).to receive(:valid?)
          .and_return(false)
        allow(validation_service).to receive(:result)
          .and_return(service_response)
        charge.valid?

        expect(Charges::Validators::PercentageService).not_to have_received(:new)
        expect(validation_service).not_to have_received(:valid?)
        expect(validation_service).not_to have_received(:result)
      end
    end
  end

  describe '#validate_volume' do
    subject(:charge) do
      build(:volume_charge, properties: charge_properties)
    end

    let(:charge_properties) { {volume_ranges: [{'foo' => 'bar'}]} }
    let(:validation_service) { instance_double(Charges::Validators::VolumeService) }

    let(:service_response) do
      BaseService::Result.new.validation_failure!(
        errors: {
          amount: ['invalid_amount'],
          volume_ranges: ['invalid_volume_ranges']
        }
      )
    end

    it 'delegates to a validation service' do
      allow(Charges::Validators::VolumeService).to receive(:new)
        .and_return(validation_service)
      allow(validation_service).to receive(:valid?)
        .and_return(false)
      allow(validation_service).to receive(:result)
        .and_return(service_response)

      aggregate_failures do
        expect(charge).not_to be_valid
        expect(charge.errors.messages.keys).to include(:properties)
        expect(charge.errors.messages[:properties]).to include('invalid_amount')
        expect(charge.errors.messages[:properties]).to include('invalid_volume_ranges')

        expect(Charges::Validators::VolumeService).to have_received(:new).with(charge:)
        expect(validation_service).to have_received(:valid?)
        expect(validation_service).to have_received(:result)
      end
    end

    context 'when charge model is not volume' do
      subject(:charge) { build(:standard_charge) }

      it 'does not apply the validation' do
        allow(Charges::Validators::VolumeService).to receive(:new)
          .and_return(validation_service)
        allow(validation_service).to receive(:valid?)
          .and_return(false)
        allow(validation_service).to receive(:result)
          .and_return(service_response)

        charge.valid?

        expect(Charges::Validators::VolumeService).not_to have_received(:new)
        expect(validation_service).not_to have_received(:valid?)
        expect(validation_service).not_to have_received(:result)
      end
    end
  end

  describe '#validate_graduated_percentage' do
    subject(:charge) do
      build(:graduated_percentage_charge, properties: charge_properties)
    end

    let(:charge_properties) do
      {graduated_percentage_ranges: [{'foo' => 'bar'}]}
    end
    let(:validation_service) { instance_double(Charges::Validators::GraduatedPercentageService) }

    let(:service_response) do
      BaseService::Result.new.validation_failure!(
        errors: {
          rate: ['invalid_rate'],
          ranges: ['invalid_graduated_percentage_ranges']
        }
      )
    end

    it 'delegates to a validation service' do
      allow(Charges::Validators::GraduatedPercentageService).to receive(:new)
        .and_return(validation_service)
      allow(validation_service).to receive(:valid?)
        .and_return(false)
      allow(validation_service).to receive(:result)
        .and_return(service_response)

      aggregate_failures do
        expect(charge).not_to be_valid
        expect(charge.errors.messages.keys).to include(:properties)
        expect(charge.errors.messages[:properties]).to include('invalid_rate')
        expect(charge.errors.messages[:properties]).to include('invalid_graduated_percentage_ranges')

        expect(Charges::Validators::GraduatedPercentageService).to have_received(:new).with(charge:)
        expect(validation_service).to have_received(:valid?)
        expect(validation_service).to have_received(:result)
      end
    end

    context 'when charge model is not graduated percentage' do
      subject(:charge) { build(:standard_charge) }

      it 'does not apply the validation' do
        allow(Charges::Validators::GraduatedPercentageService).to receive(:new)
          .and_return(validation_service)
        allow(validation_service).to receive(:valid?)
          .and_return(false)
        allow(validation_service).to receive(:result)
          .and_return(service_response)

        charge.valid?

        expect(Charges::Validators::GraduatedPercentageService).not_to have_received(:new)
        expect(validation_service).not_to have_received(:valid?)
        expect(validation_service).not_to have_received(:result)
      end
    end
  end

  describe '#validate_pay_in_advance' do
    it 'does not return an error' do
      expect(build(:standard_charge)).to be_valid
    end

    context 'when billable metric is max_agg' do
      it 'returns an error' do
        billable_metric = create(:max_billable_metric)
        charge = build(:standard_charge, :pay_in_advance, billable_metric:)

        aggregate_failures do
          expect(charge).not_to be_valid
          expect(charge.errors.messages[:pay_in_advance]).to include('invalid_aggregation_type_or_charge_model')
        end
      end
    end

    context 'when billable metric is latest_agg' do
      it 'returns an error' do
        billable_metric = create(:latest_billable_metric)
        charge = build(:standard_charge, :pay_in_advance, billable_metric:)

        aggregate_failures do
          expect(charge).not_to be_valid
          expect(charge.errors.messages[:pay_in_advance]).to include('invalid_aggregation_type_or_charge_model')
        end
      end
    end

    context 'when billable metric is weighted_sum_agg' do
      it 'returns an error' do
        billable_metric = create(:weighted_sum_billable_metric)
        charge = build(:standard_charge, :pay_in_advance, billable_metric:)

        aggregate_failures do
          expect(charge).not_to be_valid
          expect(charge.errors.messages[:pay_in_advance]).to include('invalid_aggregation_type_or_charge_model')
        end
      end
    end

    context 'when charge model is volume' do
      it 'returns an error' do
        charge = build(:volume_charge, :pay_in_advance)

        aggregate_failures do
          expect(charge).not_to be_valid
          expect(charge.errors.messages[:pay_in_advance]).to include('invalid_aggregation_type_or_charge_model')
        end
      end
    end
  end

  describe '#validate_regroup_paid_fees' do
    context 'when regroup_paid_fees is nil' do
      it 'does not return an error when' do
        expect(build(:standard_charge, pay_in_advance: true, invoiceable: true, regroup_paid_fees: nil)).to be_valid
        expect(build(:standard_charge, pay_in_advance: true, invoiceable: false, regroup_paid_fees: nil)).to be_valid
        expect(build(:standard_charge, pay_in_advance: false, invoiceable: true, regroup_paid_fees: nil)).to be_valid
        expect(build(:standard_charge, pay_in_advance: false, invoiceable: false, regroup_paid_fees: nil)).to be_valid
      end
    end

    context 'when regroup_paid_fees is `invoice`' do
      it 'requires charge to be pay_in_advance and non invoiceable' do
        expect(build(:standard_charge, pay_in_advance: true, invoiceable: false, regroup_paid_fees: 'invoice')).to be_valid

        [
          {pay_in_advance: true, invoiceable: true},
          {pay_in_advance: false, invoiceable: true},
          {pay_in_advance: false, invoiceable: false}
        ].each do |params|
          charge = build(:standard_charge, regroup_paid_fees: 'invoice', **params)

          aggregate_failures do
            expect(charge).not_to be_valid
            expect(charge.errors.messages[:regroup_paid_fees]).to include('only_compatible_with_pay_in_advance_and_non_invoiceable')
          end
        end
      end
    end
  end

  describe '#validate_min_amount_cents' do
    it 'does not return an error' do
      expect(build(:standard_charge)).to be_valid
    end

    context 'when charge is pay_in_advance' do
      it 'returns an error' do
        charge = build(:standard_charge, :pay_in_advance, min_amount_cents: 1200)

        aggregate_failures do
          expect(charge).not_to be_valid
          expect(charge.errors.messages[:min_amount_cents]).to include('not_compatible_with_pay_in_advance')
        end
      end
    end
  end

  describe '#validate_prorated' do
    let(:billable_metric) { create(:sum_billable_metric, recurring: true) }

    it 'does not return error if prorated is false and price model is percentage' do
      expect(build(:percentage_charge, prorated: false)).to be_valid
    end

    context 'when charge is standard, pay_in_advance, prorated but BM is not recurring' do
      let(:billable_metric) { create(:billable_metric, recurring: false) }

      it 'returns an error' do
        charge = build(:standard_charge, :pay_in_advance, prorated: true, billable_metric:)

        aggregate_failures do
          expect(charge).not_to be_valid
          expect(charge.errors.messages[:prorated]).to include('invalid_billable_metric_or_charge_model')
        end
      end
    end

    context 'when charge is package, pay_in_advance, prorated and BM is recurring' do
      it 'returns an error' do
        charge = build(:package_charge, :pay_in_advance, prorated: true, billable_metric:)

        aggregate_failures do
          expect(charge).not_to be_valid
          expect(charge.errors.messages[:prorated]).to include('invalid_billable_metric_or_charge_model')
        end
      end
    end

    context 'when charge is percentage, pay_in_arrear, prorated and BM is recurring' do
      it 'returns an error' do
        charge = build(:percentage_charge, prorated: true, billable_metric:)

        aggregate_failures do
          expect(charge).not_to be_valid
          expect(charge.errors.messages[:prorated]).to include('invalid_billable_metric_or_charge_model')
        end
      end
    end

    context 'when billable metric is weighted sum' do
      let(:billable_metric) { create(:weighted_sum_billable_metric) }

      it 'returns an error' do
        charge = build(:percentage_charge, prorated: true, billable_metric:)

        aggregate_failures do
          expect(charge).not_to be_valid
          expect(charge.errors.messages[:prorated]).to include('invalid_billable_metric_or_charge_model')
        end
      end
    end
  end

  describe '#validate_custom_model' do
    subject(:charge) { build(:charge, billable_metric:, charge_model: 'custom') }

    let(:billable_metric) { create(:billable_metric, aggregation_type: :count_agg) }

    it 'returns an error for invalid metric type' do
      aggregate_failures do
        expect(charge).not_to be_valid
        expect(charge.errors.messages[:charge_model]).to include('invalid_aggregation_type_or_charge_model')
      end
    end
  end
end
