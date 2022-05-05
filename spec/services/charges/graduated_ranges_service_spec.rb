# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Charges::GraduatedRangesService, type: :service do
  subject(:graduated_service) { described_class.new(ranges: ranges) }

  let(:ranges) do
    []
  end

  describe '.validate' do
    it 'ensures the presence of ranges' do
      result = graduated_service.validate

      expect(result).to include(:missing_graduated_range)
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

    context 'with no range per unit currencies' do
      let(:ranges) do
        [{ from_value: 0, to_value: nil, per_unit_price_amount_currency: nil, flat_amount_currency: 'EUR' }]
      end

      it { expect(graduated_service.validate.error).to include(:invalid_graduated_currency) }
    end

    context 'with invalid range per unit currencies' do
      let(:ranges) do
        [{ from_value: 0, to_value: nil, per_unit_price_amount_currency: 'FOO', flat_amount_currency: 'EUR' }]
      end

      it { expect(graduated_service.validate.error).to include(:invalid_graduated_currency) }
    end

    context 'with no range flat currencies' do
      let(:ranges) do
        [{ from_value: 0, to_value: nil, per_unit_price_amount_currency: 'EUR', flat_amount_currency: nil }]
      end

      it { expect(graduated_service.validate.error).to include(:invalid_graduated_currency) }
    end

    context 'with invalid range flat currencies' do
      let(:ranges) do
        [{ from_value: 0, to_value: nil, per_unit_price_amount_currency: 'EUR', flat_amount_currency: 'FOO' }]
      end

      it { expect(graduated_service.validate.error).to include(:invalid_graduated_currency) }
    end

    context 'with no range per unit amount cents' do
      let(:ranges) do
        [{ from_value: 0, to_value: nil, per_unit_price_amount_cents: nil, flat_amount_cents: 0 }]
      end

      it { expect(graduated_service.validate.error).to include(:invalid_graduated_amount) }
    end

    context 'with invalid range per unit amount cents' do
      let(:ranges) do
        [{ from_value: 0, to_value: nil, per_unit_price_amount_currency: 'foo', flat_amount_currency: 0 }]
      end

      it { expect(graduated_service.validate.error).to include(:invalid_graduated_amount) }
    end

    context 'with negative range per unit amount cents' do
      let(:ranges) do
        [{ from_value: 0, to_value: nil, per_unit_price_amount_currency: -2, flat_amount_currency: 0 }]
      end

      it { expect(graduated_service.validate.error).to include(:invalid_graduated_amount) }
    end

    context 'with no range flat amount cents' do
      let(:ranges) do
        [{ from_value: 0, to_value: nil, per_unit_price_amount_cents: 0, flat_amount_cents: nil }]
      end

      it { expect(graduated_service.validate.error).to include(:invalid_graduated_amount) }
    end

    context 'with invalid range flat amount cents' do
      let(:ranges) do
        [{ from_value: 0, to_value: nil, per_unit_price_amount_currency: 0, flat_amount_currency: 'foo' }]
      end

      it { expect(graduated_service.validate.error).to include(:invalid_graduated_amount) }
    end

    context 'with negative range flat amount cents' do
      let(:ranges) do
        [{ from_value: 0, to_value: nil, per_unit_price_amount_currency: 0, flat_amount_currency: -2 }]
      end

      it { expect(graduated_service.validate.error).to include(:invalid_graduated_amount) }
    end

    context 'with applicable ranges' do
      let(:ranges) do
        [
          {
            from_value: 0,
            to_value: 10,
            per_unit_price_amount_cents: 0,
            per_unit_price_amount_currency: 'EUR',
            flat_amount_cents: 0,
            flat_amount_currency: 'EUR',
          },
          {
            from_value: 11,
            to_value: 20,
            per_unit_price_amount_cents: 10,
            per_unit_price_amount_currency: 'EUR',
            flat_amount_cents: 20,
            flat_amount_currency: 'EUR',
          },
          {
            from_value: 21,
            to_value: nil,
            per_unit_price_amount_cents: 15,
            per_unit_price_amount_currency: 'EUR',
            flat_amount_cents: 30,
            flat_amount_currency: 'EUR',
          },
        ]
      end

      it { expect(graduated_service.validate).to be_success }
    end
  end
end
