# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Charges::Validators::PercentageService, type: :service do
  subject(:percentage_service) { described_class.new(charge: charge) }

  let(:charge) { build(:percentage_charge, properties: percentage_properties) }

  let(:percentage_properties) do
    {
      rate: '0.25',
      fixed_amount: '2',
      fixed_amount_target: 'all_units',
    }
  end

  describe 'validate' do
    it { expect(percentage_service.validate).to be_success }

    context 'without rate' do
      let(:percentage_properties) do
        {
          fixed_amount: '2',
          fixed_amount_target: 'all_units',
        }
      end

      it { expect(percentage_service.validate.error).to include(:invalid_rate) }
    end

    context 'when given rate is not string' do
      let(:percentage_properties) do
        {
          rate: 0.25,
          fixed_amount: '2',
          fixed_amount_target: 'all_units',
        }
      end

      it { expect(percentage_service.validate.error).to include(:invalid_rate) }
    end

    context 'when rate cannot be converted to numeric format' do
      let(:percentage_properties) do
        {
          rate: 'bla',
          fixed_amount: '2',
          fixed_amount_target: 'all_units',
        }
      end

      it { expect(percentage_service.validate.error).to include(:invalid_rate) }
    end

    context 'with negative rate' do
      let(:percentage_properties) do
        {
          rate: '-0.50',
          fixed_amount: '2',
          fixed_amount_target: 'all_units',
        }
      end

      it { expect(percentage_service.validate.error).to include(:invalid_rate) }
    end

    context 'when rate is zero' do
      let(:percentage_properties) do
        {
          rate: '0.00',
          fixed_amount: '2',
          fixed_amount_target: 'all_units',
        }
      end

      it { expect(percentage_service.validate.error).to include(:invalid_rate) }
    end

    context 'without fixed amount' do
      let(:percentage_properties) do
        {
          rate: '0.25',
          fixed_amount_target: 'all_units',
        }
      end

      it { expect(percentage_service.validate.error).to include(:invalid_fixed_amount) }
    end

    context 'when fixed amount cannot be converted to numeric format' do
      let(:percentage_properties) do
        {
          rate: '0.25',
          fixed_amount: 'bla',
          fixed_amount_target: 'all_units',
        }
      end

      it { expect(percentage_service.validate.error).to include(:invalid_fixed_amount) }
    end

    context 'when given fixed amount is not string' do
      let(:percentage_properties) do
        {
          rate: '0.25',
          fixed_amount: 2,
          fixed_amount_target: 'all_units',
        }
      end

      it { expect(percentage_service.validate.error).to include(:invalid_fixed_amount) }
    end

    context 'with negative fixed amount' do
      let(:percentage_properties) do
        {
          rate: '0.25',
          fixed_amount: '-2',
          fixed_amount_target: 'all_units',
        }
      end

      it { expect(percentage_service.validate.error).to include(:invalid_fixed_amount) }
    end

    context 'without fixed amount target' do
      let(:percentage_properties) do
        {
          rate: '0.25',
          fixed_amount: '2',
        }
      end

      it { expect(percentage_service.validate.error).to include(:invalid_fixed_amount_target) }
    end

    context 'without fixed amount and fixed amount target' do
      let(:percentage_properties) do
        {
          rate: '0.25'
        }
      end

      it { expect(percentage_service.validate.error).to be nil }
    end

    context 'when fixed amount target is not string' do
      let(:percentage_properties) do
        {
          rate: '0.25',
          fixed_amount: '2',
          fixed_amount_target: 5,
        }
      end

      it { expect(percentage_service.validate.error).to include(:invalid_fixed_amount_target) }
    end

    context 'when fixed amount target is not either all_units or each_unit' do
      let(:percentage_properties) do
        {
          rate: '0.25',
          fixed_amount: '2',
          fixed_amount_target: 'bbb',
        }
      end

      it { expect(percentage_service.validate.error).to include(:invalid_fixed_amount_target) }
    end
  end
end
