# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Invoices::CreateGeneratingService, type: :service do
  subject(:create_service) do
    described_class.new(customer:, invoice_type:, currency:, datetime:, subscriptions_details:)
  end

  let(:customer) { create(:customer) }
  let(:invoice_type) { :one_off }
  let(:currency) { 'EUR' }
  let(:datetime) { Time.current }
  let(:subscriptions_details) { [] }
  let(:recurring) { false }

  describe 'call' do
    it 'creates an invoice' do
      result = create_service.call

      expect(result).to be_success
      expect(result.invoice).to be_persisted
      expect(result.invoice).to be_generating
      expect(result.invoice.organization).to eq(customer.organization)
      expect(result.invoice.customer).to eq(customer)
      expect(result.invoice).to be_one_off
      expect(result.invoice.currency).to eq(currency)
      expect(result.invoice.timezone).to eq(customer.applicable_timezone)
      expect(result.invoice.issuing_date).to eq(datetime.to_date)
      expect(result.invoice.payment_due_date).to eq(datetime.to_date)
      expect(result.invoice.net_payment_term).to eq(customer.applicable_net_payment_term)
    end

    context 'with customer timezone' do
      let(:customer) { create(:customer, timezone: 'America/Los_Angeles') }
      let(:datetime) { Time.zone.parse('2022-11-25 01:00:00') }

      it 'assigns the issuing date in the customer timezone' do
        result = create_service.call

        expect(result.invoice.timezone).to eq('America/Los_Angeles')
        expect(result.invoice.issuing_date.to_s).to eq('2022-11-24')
      end
    end

    context 'with applicable net payment term' do
      let(:customer) { create(:customer, net_payment_term: 3) }

      it 'assigns the payment due date based on the net payment term' do
        result = create_service.call

        expect(result.invoice.net_payment_term).to eq(3)
        expect(result.invoice.payment_due_date.to_s).to eq((datetime + 3.days).to_date.to_s)
      end
    end

    context 'when a block is passed to the method' do
      let(:invoice_type) { :subscription }
      let(:subscription) { create(:subscription, customer:, started_at: Time.current - 1.day) }

      it 'creates an invoice' do
        result = create_service.call do |invoice|
          invoice.invoice_subscriptions.create!(
            subscription:,
            recurring:,
            from_datetime: datetime.beginning_of_month,
            to_datetime: datetime.end_of_month,
            charges_from_datetime: datetime.end_of_month,
            charges_to_datetime: datetime.end_of_month,
          )
        end

        expect(result).to be_success
        expect(result.invoice).to be_persisted
        expect(result.invoice).to be_generating
        expect(result.invoice.organization).to eq(customer.organization)
        expect(result.invoice.customer).to eq(customer)
        expect(result.invoice).to be_subscription
        expect(result.invoice.currency).to eq(currency)
        expect(result.invoice.timezone).to eq(customer.applicable_timezone)
        expect(result.invoice.issuing_date).to eq(datetime.to_date)
        expect(result.invoice.payment_due_date).to eq(datetime.to_date)
        expect(result.invoice.net_payment_term).to eq(customer.applicable_net_payment_term)

        expect(result.invoice.invoice_subscriptions.count).to eq(1)
      end
    end

    context 'when invoice type is subscription' do
      let(:invoice_type) { :subscription }
      let(:customer) { create(:customer, invoice_grace_period: 3) }

      it 'creates an invoice with grace period' do
        result = create_service.call

        expect(result.invoice.issuing_date.to_s).to eq((datetime + 3.days).to_date.to_s)
      end

      context 'with customer timezone' do
        let(:customer) { create(:customer, timezone: 'America/Los_Angeles', invoice_grace_period: 3) }
        let(:datetime) { Time.zone.parse('2022-11-25 01:00:00') }

        it 'assigns the issuing date in the customer timezone' do
          result = create_service.call

          expect(result.invoice.timezone).to eq('America/Los_Angeles')
          expect(result.invoice.issuing_date.to_s).to eq('2022-11-27')
        end
      end
    end
  end
end
