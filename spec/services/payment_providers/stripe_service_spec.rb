# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PaymentProviders::StripeService, type: :service do
  subject(:stripe_service) { described_class.new(membership.user) }

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }

  let(:public_key) { SecureRandom.uuid }
  let(:secret_key) { SecureRandom.uuid }

  describe '.create_or_update' do
    it 'creates a stripe provider' do
      expect do
        stripe_service.create_or_update(
          organization_id: organization.id,
          secret_key: secret_key,
          create_customers: true,
          send_zero_amount_invoice: false,
        )
      end.to change(PaymentProviders::StripeProvider, :count).by(1)
    end

    context 'when organization already have a stripe provider' do
      let(:stripe_provider) { create(:stripe_provider, organization: organization) }

      before { stripe_provider }

      it 'updates the existing provider' do
        result = stripe_service.create_or_update(
          organization_id: organization.id,
          secret_key: secret_key,
          create_customers: true,
          send_zero_amount_invoice: false,
        )

        expect(result).to be_success

        aggregate_failures do
          expect(result.stripe_provider.id).to eq(stripe_provider.id)
          expect(result.stripe_provider.secret_key).to eq(secret_key)
          expect(result.stripe_provider.create_customers).to be_truthy
          expect(result.stripe_provider.send_zero_amount_invoice).to be_falsey
        end
      end
    end

    context 'with validation error' do
      it 'returns an error result' do
        result = stripe_service.create_or_update(
          organization_id: organization.id,
          secret_key: nil,
        )

        expect(result).not_to be_success
        expect(result.error).to eq('Validation error on the record')
      end
    end
  end
end
