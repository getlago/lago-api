# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Charges::Validators::PackageService, type: :service do
  subject(:package_service) { described_class.new(charge: charge) }

  let(:charge) { build(:package_charge, properties: package_properties) }

  let(:package_properties) do
    {
      package_size: 10,
      free_units: 10,
      amount: '100',
    }
  end

  describe 'validate' do
    it { expect(package_service.validate).to be_success }

    context 'without amount' do
      let(:package_properties) do
        {
          package_size: 10,
          free_units: 10,
        }
      end

      it { expect(package_service.validate.error).to include(:invalid_amount) }
    end

    context 'when amount is not numeric' do
      let(:package_properties) do
        {
          package_size: 10,
          free_units: 10,
          amount: 'foo',
        }
      end

      it { expect(package_service.validate.error).to include(:invalid_amount) }
    end

    context 'with negative amount' do
      let(:package_properties) do
        {
          package_size: 10,
          free_units: 10,
          amount: '-3',
        }
      end

      it { expect(package_service.validate.error).to include(:invalid_amount) }
    end

    context 'without package size' do
      let(:package_properties) do
        {
          free_units: 10,
          amount: '100',
        }
      end

      it { expect(package_service.validate.error).to include(:invalid_package_size) }
    end

    context 'when package size is not numeric' do
      let(:package_properties) do
        {
          package_size: 'foo',
          free_units: 10,
          amount: '100',
        }
      end

      it { expect(package_service.validate.error).to include(:invalid_package_size) }
    end

    context 'with negative package size' do
      let(:package_properties) do
        {
          package_size: -3,
          free_units: 10,
          amount: '100',
        }
      end

      it { expect(package_service.validate.error).to include(:invalid_package_size) }
    end

    context 'with zero package size' do
      let(:package_properties) do
        {
          package_size: 0,
          free_units: 10,
          amount: '100',
        }
      end

      it { expect(package_service.validate.error).to include(:invalid_package_size) }
    end

    context 'without free units size' do
      let(:package_properties) do
        {
          package_size: 10,
          amount: '100',
        }
      end

      it { expect(package_service.validate.error).to include(:invalid_free_units) }
    end

    context 'when free units are not numeric' do
      let(:package_properties) do
        {
          package_size: 10,
          free_units: 'foo',
          amount: '100',
        }
      end

      it { expect(package_service.validate.error).to include(:invalid_free_units) }
    end

    context 'with negative free units' do
      let(:package_properties) do
        {
          package_size: 10,
          free_units: -3,
          amount: '100',
        }
      end

      it { expect(package_service.validate.error).to include(:invalid_free_units) }
    end
  end
end
