# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Analytics::GrossRevenuesService, type: :service do
  let(:service) { described_class.new(organization) }
  let(:customer) { create(:customer, organization:) }
  let(:organization) { create(:organization) }

  describe '#call' do
    subject(:service_call) { service.call }

    context 'when licence is premium' do
      around { |test| lago_premium!(&test) }

      it 'returns success' do
        expect(service_call).to be_success
      end
    end

    context 'when licence is not premium' do
      it 'returns success' do
        expect(service_call).to be_success
      end
    end
  end
end
