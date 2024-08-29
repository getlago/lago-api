# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Invoices::RefreshDraftService, type: :service do
  subject(:refresh_service) { described_class.new(invoice:) }

  describe '#call' do
    let(:status) { :draft }
    let(:invoice) do
      create(
        :invoice,
        status:,
        organization:,
        customer:,
        taxes_amount_cents: 10,
        total_amount_cents: 1000110010,
        taxes_rate: 30,
        fees_amount_cents: 2600,
        sub_total_excluding_taxes_amount_cents: 9900090,
        sub_total_including_taxes_amount_cents: 9900100
      )
    end

    let(:started_at) { 1.month.ago.beginning_of_month }
    let(:customer) { create(:customer) }
    let(:organization) { customer.organization }

    let(:subscription) do
      create(
        :subscription,
        customer:,
        organization:,
        subscription_at: started_at,
        started_at:,
        created_at: started_at
      )
    end

    let(:invoice_subscription) { create(:invoice_subscription, invoice:, subscription:, recurring: true) }
    let(:tax) { create(:tax, organization:, rate: 15) }

    before do
      invoice_subscription
      tax
      allow(Invoices::CalculateFeesService).to receive(:call).and_call_original
    end

    context 'when invoice is ready to be finalized' do
      let(:invoice) do
        create(:invoice, status:, organization:, customer:, ready_to_be_refreshed: true)
      end

      it 'updates ready_to_be_refreshed to false' do
        expect { refresh_service.call }.to change(invoice, :ready_to_be_refreshed).to(false)
      end
    end

    context 'when invoice is finalized' do
      let(:status) { :finalized }

      it 'does not refresh it' do
        result = refresh_service.call
        expect(Invoices::CalculateFeesService).not_to have_received(:call)
        expect(result).to be_success
      end
    end

    context 'when refreshing upgrading invoice' do
      let(:invoice2) do
        create(:invoice, status:, organization:, customer:)
      end
      let(:invoice_subscription) do
        create(
          :invoice_subscription,
          invoice:,
          subscription:,
          recurring: false,
          invoicing_reason: 'subscription_terminating'
        )
      end
      let(:invoice_subscription2) do
        create(
          :invoice_subscription,
          invoice:,
          subscription: subscription2,
          recurring: false,
          invoicing_reason: 'subscription_starting'
        )
      end
      let(:invoice_subscription3) do
        create(
          :invoice_subscription,
          invoice: invoice2,
          subscription: subscription2,
          recurring: false,
          invoicing_reason: 'subscription_terminating'
        )
      end
      let(:subscription) do
        create(
          :subscription,
          customer:,
          organization:,
          subscription_at: started_at - 1.month,
          started_at: started_at - 1.month,
          created_at: started_at - 1.month,
          terminated_at: started_at,
          status: :terminated
        )
      end
      let(:subscription2) do
        create(
          :subscription,
          customer:,
          organization:,
          subscription_at: started_at,
          started_at:,
          created_at: started_at,
          previous_subscription_id: subscription.id
        )
      end

      before do
        invoice_subscription2
        invoice_subscription3

        subscription2.mark_as_terminated!

        allow(Invoices::CalculateFeesService).to receive(:call).and_return(BaseService::Result.new)

        invoice.update!(created_at: started_at)
      end

      it 'correctly creates invoice_subscriptions without duplicating invoicing reason' do
        refresh_service.call

        expect(invoice.reload.invoice_subscriptions.pluck(:invoicing_reason))
          .to match_array(%w[subscription_terminating subscription_starting])
      end
    end

    it 'regenerates fees' do
      fee = create(:fee, invoice:)
      create(:standard_charge, plan: subscription.plan, charge_model: 'standard')

      expect { refresh_service.call }
        .to change { invoice.reload.fees.count }.from(1).to(2)
        .and change { invoice.fees.pluck(:id).include?(fee.id) }.from(true).to(false)
        .and change { invoice.fees.pluck(:created_at).uniq }.to([invoice.created_at])

      expect(invoice.invoice_subscriptions.first.recurring).to be_truthy
    end

    it 'assigns credit notes to new created fee' do
      credit_note = create(:credit_note, invoice:)
      fee = create(:fee, invoice:, subscription:)
      create(:credit_note_item, credit_note:, fee:)

      expect { refresh_service.call }.to change { credit_note.reload.items.pluck(:fee_id) }
    end

    it 'updates taxes_rate' do
      expect { refresh_service.call }
        .to change { invoice.reload.taxes_rate }.from(30.0).to(15)
    end

    context 'when there is a tax_integration set up' do
      let(:integration) { create(:anrok_integration, organization:) }
      let(:integration_customer) { create(:anrok_customer, integration:, customer:) }
      let(:response) { instance_double(Net::HTTPOK) }
      let(:lago_client) { instance_double(LagoHttpClient::Client) }
      let(:endpoint) { 'https://api.nango.dev/v1/anrok/draft_invoices' }
      let(:integration_collection_mapping) do
        create(
          :netsuite_collection_mapping,
          integration:,
          mapping_type: :fallback_item,
          settings: {external_id: '1', external_account_code: '11', external_name: ''}
        )
      end
      let(:charge) { create(:standard_charge, plan: subscription.plan, charge_model: 'standard') }

      before do
        integration_collection_mapping
        integration_customer
        charge

        allow(LagoHttpClient::Client).to receive(:new).with(endpoint).and_return(lago_client)
        allow(lago_client).to receive(:post_with_response).and_return(response)
        allow(response).to receive(:body).and_return(body)
      end

      context 'when successfully fetching taxes' do
        let(:body) do
          p = Rails.root.join('spec/fixtures/integration_aggregator/taxes/invoices/success_response_multiple_fees.json')
          json = File.read(p)
          response = JSON.parse(json)

          response['succeededInvoices'].first['fees'].first['item_id'] = subscription.id
          response['succeededInvoices'].first['fees'].second['item_id'] = charge.billable_metric.id
          response.to_json
        end

        it 'successfully applies taxes and regenerates fees' do
          expect { refresh_service.call }.to change { invoice.reload.taxes_rate }.from(30.0).to(10.0)
            .and change { invoice.fees.count }.from(0).to(2)
        end
      end

      context 'when failed to fetch taxes' do
        let(:body) do
          p = Rails.root.join('spec/fixtures/integration_aggregator/taxes/invoices/failure_response.json')
          json = File.read(p)
          response = JSON.parse(json)
          response.to_json
        end

        it 'regenerates fees' do
          expect { refresh_service.call }.to change { invoice.fees.count }.from(0).to(2)
        end

        it 'creates error_detail for the invoice' do
          result = refresh_service.call

          aggregate_failures do
            expect(result.success?).to be(false)
            expect(invoice.reload.error_details.count).to eq(1)
            expect(invoice.error_details.last.error_code).to include('tax_error')
          end
        end

        it 'resets invoice values to calculatable before the error' do
          expect { refresh_service.call }.to change(invoice.reload, :taxes_amount_cents).from(10).to(0)
            .and change(invoice, :total_amount_cents).from(1000110010).to(0)
            .and change(invoice, :taxes_rate).from(30.0).to(0)
            .and change(invoice, :fees_amount_cents).from(2600).to(100)
            .and change(invoice, :sub_total_excluding_taxes_amount_cents).from(9900090).to(100)
            .and change(invoice, :sub_total_including_taxes_amount_cents).from(9900100).to(0)
        end
      end
    end

    it 'flags lifetime usage for refresh' do
      create(:usage_threshold, plan: subscription.plan)

      refresh_service.call

      expect(subscription.reload.lifetime_usage.recalculate_invoiced_usage).to be(true)
    end
  end
end
