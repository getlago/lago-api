# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Invoices::CreateService, type: :service do
  subject(:invoice_service) do
    described_class.new(subscription: subscription, timestamp: timestamp.to_i)
  end

  describe 'create' do
    let(:subscription) { create(:subscription, plan: plan, started_at: Time.zone.now - 2.years) }

    context 'when billed monthly on begging of period' do
      let(:timestamp) { Time.zone.now.beginning_of_month }

      let(:plan) do
        create(:plan, interval: 'monthly', frequency: 'beginning_of_period')
      end

      it 'creates an invoice' do
        result = invoice_service.create

        aggregate_failures do
          expect(result).to be_success

          expect(result.invoice.to_date).to eq(timestamp - 1.day)
          expect(result.invoice.from_date).to eq(timestamp - 1.month)
          expect(result.invoice.subscription).to eq(subscription)
          expect(result.invoice.issuing_date.to_date).to eq(timestamp - 1.day)
          expect(result.invoice.fees.count).to eq(1)
        end
      end
    end

    context 'when billed monthly on subscription anniversary' do
      let(:timestamp) { subscription.started_at + 2.years }
      let(:plan) do
        create(:plan, interval: 'monthly', frequency: 'subscription_date')
      end

      it 'creates an invoice' do
        result = invoice_service.create

        aggregate_failures do
          expect(result).to be_success

          expect(result.invoice.to_date).to eq((timestamp - 1.day).to_date)
          expect(result.invoice.from_date).to eq((timestamp - 1.month).to_date)
          expect(result.invoice.subscription).to eq(subscription)
          expect(result.invoice.fees.count).to eq(1)
        end
      end
    end

    context 'when billed monthly on first month' do
      let(:timestamp) { Time.zone.now.beginning_of_month }

      let(:started_at) { timestamp - 3.days }
      let(:subscription) { create(:subscription, plan: plan, started_at: started_at) }

      let(:plan) do
        create(:plan, interval: 'monthly', frequency: 'beginning_of_period')
      end

      it 'creates an invoice' do
        result = invoice_service.create

        aggregate_failures do
          expect(result).to be_success

          expect(result.invoice.to_date).to eq(timestamp - 1.day)
          expect(result.invoice.from_date).to eq(started_at)
          expect(result.invoice.subscription).to eq(subscription)
          expect(result.invoice.fees.count).to eq(1)
        end
      end
    end

    context 'when billed yearly on begging of period' do
      let(:timestamp) { Time.zone.now.beginning_of_month }

      let(:plan) do
        create(:plan, interval: 'yearly', frequency: 'beginning_of_period')
      end

      it 'creates an invoice' do
        result = invoice_service.create

        aggregate_failures do
          expect(result).to be_success

          expect(result.invoice.to_date).to eq(timestamp - 1.day)
          expect(result.invoice.from_date).to eq(timestamp - 1.year)
          expect(result.invoice.subscription).to eq(subscription)
          expect(result.invoice.fees.count).to eq(1)
        end
      end
    end

    context 'when billed yearly on subscription anniversary' do
      let(:timestamp) { subscription.started_at + 2.years }

      let(:plan) do
        create(:plan, interval: 'yearly', frequency: 'subscription_date')
      end

      it 'creates an invoice' do
        result = invoice_service.create

        aggregate_failures do
          expect(result).to be_success

          expect(result.invoice.to_date).to eq((timestamp - 1.day).to_date)
          expect(result.invoice.from_date).to eq((timestamp - 1.year).to_date)
          expect(result.invoice.subscription).to eq(subscription)
          expect(result.invoice.fees.count).to eq(1)
        end
      end
    end

    context 'when billed yearly on first year' do
      let(:plan) do
        create(:plan, interval: 'yearly', frequency: 'beginning_of_period')
      end

      let(:timestamp) { Time.zone.now.beginning_of_month }
      let(:started_at) { Time.zone.today - 3.months }
      let(:subscription) { create(:subscription, plan: plan, started_at: started_at) }

      it 'creates an invoice' do
        result = invoice_service.create

        aggregate_failures do
          expect(result).to be_success

          expect(result.invoice.to_date).to eq(timestamp - 1.day)
          expect(result.invoice.from_date).to eq(started_at)
          expect(result.invoice.subscription).to eq(subscription)
          expect(result.invoice.fees.count).to eq(1)
        end
      end
    end

    context 'when plan is pay in advance' do
      let(:plan) do
        create(:plan, interval: 'yearly', frequency: 'beginning_of_period', pay_in_advance: true)
      end

      let(:timestamp) { Time.zone.now.beginning_of_month }
      let(:started_at) { Time.zone.today - 3.months }
      let(:subscription) { create(:subscription, plan: plan, started_at: started_at) }

      it 'creates an invoice' do
        result = invoice_service.create

        aggregate_failures do
          expect(result.invoice.issuing_date).to eq(timestamp.to_date)
        end
      end
    end
  end
end
