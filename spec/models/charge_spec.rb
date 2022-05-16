# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Charge, type: :model do
  describe '.validate_graduated_range' do
    subject(:charge) do
      build(:graduated_charge, properties: charge_properties)
    end

    let(:charge_properties) { [{ 'foo' => 'bar' }] }
    let(:validation_service) { instance_double(Charges::Validators::GraduatedService) }

    let(:service_response) do
      BaseService::Result.new.fail!(
        :invalid_properties,
        [
          :invalid_amount,
          :invalid_graduated_ranges,
        ],
      )
    end

    it 'delegates to a validation service' do
      allow(Charges::Validators::GraduatedService).to receive(:new)
        .and_return(validation_service)
      allow(validation_service).to receive(:validate)
        .and_return(service_response)

      aggregate_failures do
        expect(charge).not_to be_valid
        expect(charge.errors.messages.keys).to include(:properties)
        expect(charge.errors.messages[:properties]).to include('invalid_amount')
        expect(charge.errors.messages[:properties]).to include('invalid_graduated_ranges')

        expect(Charges::Validators::GraduatedService).to have_received(:new)
          .with(charge: charge)
        expect(validation_service).to have_received(:validate)
      end
    end

    context 'when charge model is not graduated' do
      subject(:charge) { build(:standard_charge) }

      it 'does not apply the validation' do
        allow(Charges::Validators::GraduatedService).to receive(:new)
          .and_return(validation_service)
        allow(validation_service).to receive(:validate)
          .and_return(service_response)

        charge.valid?

        expect(Charges::Validators::GraduatedService).not_to have_received(:new)
        expect(validation_service).not_to have_received(:validate)
      end
    end
  end

  describe '.validate_amount' do
    subject(:charge) do
      build(:standard_charge, properties: charge_properties)
    end

    let(:charge_properties) { [{ 'foo' => 'bar' }] }
    let(:validation_service) { instance_double(Charges::Validators::StandardService) }

    let(:service_response) do
      BaseService::Result.new.fail!(
        :invalid_properties,
        [:invalid_amount],
      )
    end

    it 'delegates to a validation service' do
      allow(Charges::Validators::StandardService).to receive(:new)
        .and_return(validation_service)
      allow(validation_service).to receive(:validate)
        .and_return(service_response)

      aggregate_failures do
        expect(charge).not_to be_valid
        expect(charge.errors.messages.keys).to include(:properties)
        expect(charge.errors.messages[:properties]).to include('invalid_amount')

        expect(Charges::Validators::StandardService).to have_received(:new)
          .with(charge: charge)
        expect(validation_service).to have_received(:validate)
      end
    end

    context 'when charge model is not graduated' do
      subject(:charge) { build(:graduated_charge) }

      it 'does not apply the validation' do
        allow(Charges::Validators::StandardService).to receive(:new)
          .and_return(validation_service)
        allow(validation_service).to receive(:validate)
          .and_return(service_response)

        charge.valid?

        expect(Charges::Validators::StandardService).not_to have_received(:new)
        expect(validation_service).not_to have_received(:validate)
      end
    end
  end
end
