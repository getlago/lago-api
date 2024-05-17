# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Taxes::CreateService, type: :service do
  subject(:create_service) { described_class.new(organization:, params:) }

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:code) { 'tax_code' }
  let(:params) do
    {
      name: 'Tax',
      code:,
      rate: 15.0,
      description: 'Tax Description'
    }
  end

  describe '#call' do
    it 'creates a tax' do
      expect { create_service.call }.to change(Tax, :count).by(1)
    end

    it 'returns tax in the result' do
      result = create_service.call
      expect(result.tax).to be_a(Tax)
    end

    context 'with validation error' do
      before { create(:tax, organization:, code:) }

      it 'returns an error' do
        result = create_service.call

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages[:code]).to eq(['value_already_exist'])
        end
      end
    end
  end
end
