# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Charge, type: :model do
  describe '.validate_graduated_range' do
    subject(:charge) do
      build(:charge, charge_model: :graduated, properties: charge_properties)
    end

    let(:charge_properties) { [{ 'foo' => 'bar' }] }
    let(:validation_service) { instance_double(Charges::GraduatedRangesService) }

    it 'delegates to a validation service' do
      allow(Charges::GraduatedRangesService).to receive(:new)
        .and_return(validation_service)
      allow(validation_service).to receive(:validate)
        .and_return(
          [
            :invalid_graduated_amount,
            :invalid_graduated_currency,
            :invalid_graduated_ranges,
          ],
        )

      aggregate_failures do
        expect(charge).not_to be_valid
        expect(charge.errors.messages.keys).to include(:properties)
        expect(charge.errors.messages[:properties]).to include('invalid_graduated_amount')
        expect(charge.errors.messages[:properties]).to include('invalid_graduated_currency')
        expect(charge.errors.messages[:properties]).to include('invalid_graduated_ranges')

        expect(Charges::GraduatedRangesService).to have_received(:new)
          .with(charge_properties)
        expect(validation_service).to have_received(:validate)
      end
    end

    context 'when charge model is not graduated' do
      subject(:charge) do
        build(:charge, charge_model: :standard, properties: charge_properties)
      end

      it 'does not apply the validation' do
        allow(Charges::GraduatedRangesService).to receive(:new)
          .and_return(validation_service)
        allow(validation_service).to receive(:validate)
          .and_return([])

        charge.valid?

        expect(Charges::GraduatedRangesService).not_to have_received(:new)
        expect(validation_service).not_to have_received(:validate)
      end
    end
  end
end
