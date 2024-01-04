# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Invoices::Payments::PinetService, type: :service do
  subject(:pinet_service) { described_class.new(invoice) }

  let(:customer) { create(:customer) }
  let(:organization) { customer.organization }
  let(:pinet_payment_provider) { create(:pinet_provider, organization:) }
  let(:pinet_customer) { create(:pinet_customer, customer:, payment_token: 'pt_123456') }

  let(:invoice) do
    create(
      :invoice,
      organization:,
      customer:,
      total_amount_cents: 200,
      currency: 'EUR',
      ready_for_payment_processing: true,
    )
  end

  describe '.create' do
    # Mocking Pinet Client behavior
    let(:pinet_client) { instance_double(Pinet::Client) }

    before do
      pinet_payment_provider
      pinet_customer

      allow(pinet_client).to receive(:charge).and_return(
        OpenStruct.new(
          id: 'ch_123456',
          status: 'succeeded',
          amount: invoice.total_amount_cents,
          currency: invoice.currency,
        ),
      )
      allow(Pinet::Client).to receive(:new).and_return(pinet_client)
    end

    it 'creates a pinet payment and a payment' do
      result = pinet_service.create

      expect(result).to be_success
    end
  end

  describe '.update_payment_status' do
    let(:payment) do
      create(
        :payment,
        invoice:,
        provider_payment_id: 'ch_123456',
      )
    end

    before do
      payment
    end

    it 'updates the payment and invoice status' do
      result = pinet_service.update_payment_status(
        organization_id: organization.id,
        provider_payment_id: 'ch_123456',
        status: 'succeeded',
      )

      expect(result).to be_success
    end
  end
end
