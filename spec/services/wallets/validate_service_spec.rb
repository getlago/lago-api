# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Wallets::ValidateService, type: :service do
  subject(:validate_service) { described_class.new(result, **args) }

  let(:result) { BaseService::Result.new }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization: organization) }
  let(:subscription) { create(:subscription, customer: customer) }
  let(:paid_credits) { '1.00' }
  let(:granted_credits) { '0.00' }
  let(:args) do
    {
      customer_id: customer.id,
      paid_credits: paid_credits,
      granted_credits: granted_credits,
    }
  end

  before { subscription }

  describe '.valid?' do
    it 'returns true' do
      byebug
      expect(validate_service).to be_valid
    end
  end
end
