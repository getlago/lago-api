# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Charges::Validators::GraduatedService, type: :service do
  subject(:graduated_service) { described_class.new(charge: charge) }

  let(:charge) { build(:graduated_charge, properties: ranges) }

  let(:ranges) do
    []
  end

  describe '.validate' do
    it 'ensures the presence of ranges' do
      result = graduated_service.validate

      expect(result.error).to include(:missing_graduated_range)
    end

    context 'when ranges does not starts at 0' do
      let(:ranges) do
        [{ from_value: -1, to_value: 100 }]
      end

      it { expect(graduated_service.validate.error).to include(:invalid_graduated_ranges) }
    end

    context 'when ranges does not ends at infinity' do
      let(:ranges) do
        [{ from_value: 0, to_value: 100 }]
      end

      it { expect(graduated_service.validate.error).to include(:invalid_graduated_ranges) }
    end

    context 'when ranges have holes' do
      let(:ranges) do
        [
          { from_value: 0, to_value: 100 },
          { from_value: 120, to_value: 100 },
        ]
      end

      it { expect(graduated_service.validate.error).to include(:invalid_graduated_ranges) }
    end

    context 'when ranges are overlapping' do
      let(:ranges) do
        [
          { from_value: 0, to_value: 100 },
          { from_value: 90, to_value: 100 },
        ]
      end

      it { expect(graduated_service.validate.error).to include(:invalid_graduated_ranges) }
    end

    context 'with no range per unit amount cents' do
      let(:ranges) do
        [{ from_value: 0, to_value: nil, per_unit_amount: nil, flat_amount: '0' }]
      end

      it { expect(graduated_service.validate.error).to include(:invalid_amount) }
    end

    context 'with invalid range per unit amount cents' do
      let(:ranges) do
        [{ from_value: 0, to_value: nil, per_unit_amount: 'foo', flat_amount: '0' }]
      end

      it { expect(graduated_service.validate.error).to include(:invalid_amount) }
    end

    context 'with negative range per unit amount cents' do
      let(:ranges) do
        [{ from_value: 0, to_value: nil, per_unit_amount: '-2', flat_amount: 0 }]
      end

      it { expect(graduated_service.validate.error).to include(:invalid_amount) }
    end

    context 'with no range flat amount cents' do
      let(:ranges) do
        [{ from_value: 0, to_value: nil, per_unit_amount: '0', flat_amount: nil }]
      end

      it { expect(graduated_service.validate.error).to include(:invalid_amount) }
    end

    context 'with invalid range flat amount cents' do
      let(:ranges) do
        [{ from_value: 0, to_value: nil, per_unit_amount: '0', flat_amount: 'foo' }]
      end

      it { expect(graduated_service.validate.error).to include(:invalid_amount) }
    end

    context 'with negative range flat amount cents' do
      let(:ranges) do
        [{ from_value: 0, to_value: nil, per_unit_amount: '0', flat_amount: '-2' }]
      end

      it { expect(graduated_service.validate.error).to include(:invalid_amount) }
    end

    context 'with applicable ranges' do
      let(:ranges) do
        [
          {
            from_value: 0,
            to_value: 10,
            per_unit_amount: '0',
            flat_amount: '0',
          },
          {
            from_value: 11,
            to_value: 20,
            per_unit_amount: '10',
            flat_amount: '20',
          },
          {
            from_value: 21,
            to_value: nil,
            per_unit_amount: '15',
            flat_amount: '30',
          },
        ]
      end

      it { expect(graduated_service.validate).to be_success }
    end
  end
end
