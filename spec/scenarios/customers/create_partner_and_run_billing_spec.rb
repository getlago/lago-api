# frozen_string_literal: true

require 'rails_helper'

describe 'Create partner and run billing Scenarios', :scenarios, type: :request do
  let(:organization) { create(:organization, webhook_url: nil, document_numbering: 'per_organization') }
  let(:partner) { create(:customer, organization:,) }
  let(:customers) { create_list(:customer, 2, organization:,) }
  let(:plan) { create(:plan, organization:) }
  let(:metric) { create(:latest_billable_metric, organization:) }
  let(:params) do
    {code: metric.code, transaction_id: SecureRandom.uuid}
  end

  it 'allows to switch customer to partner before customer has assigned plans' do
    expect do
      create_or_update_customer(
        {
          external_id: partner.external_id,
          account_type: 'partner'
        }
      )
    end.to change {partner.reload.account_type }.from('customer').to('partner')
      .and change {partner.exclude_from_dunning_campaign }.from(false).to(true)

    create_subscription(
      {
        external_customer_id: partner.external_id,
        external_id: partner.external_id,
        plan_code: plan.code
      }
    )

    expect do
      create_or_update_customer(
        {
          external_id: partner.external_id,
          account_type: 'customer'
        }
      )
    end.not_to change(partner.reload, :account_type)
  end

  it 'creates partner-specific invoices without integrations, payments, with partner numbering, excluded from analytics' do
    create_or_update_customer(
      {
        external_id: partner.external_id,
        account_type: 'partner'
      }
    )

    ### 24 Apr: Create subscriptions + charges.
    apr24 = Time.zone.parse('2024-04-24')
    travel_to(apr24) do
      create(
        :package_charge,
        plan: plan,
        billable_metric: metric,
        pay_in_advance: false,
        prorated: false,
        invoiceable: true,
        properties: {
          amount: '2',
          free_units: 1000,
          package_size: 1000
        }
      )

      customers.each do |customer|
        create_subscription(
          {
            external_customer_id: customer.external_id,
            external_id: customer.external_id,
            plan_code: plan.code
          }
        )
      end
      create_subscription(
        {
          external_customer_id: partner.external_id,
          external_id: partner.external_id,
          plan_code: plan.code
        }
      )
    end

    ### 25 Apr: Ingest events for Plan 1.
    apr24 = Time.zone.parse('2024-04-24')
    travel_to(apr24) do
      plan.subscriptions.each do |subscription|
        create_event(
          params.merge(
            external_subscription_id: subscription.external_id
          )
        )
      end
      perform_all_enqueued_jobs
    end

    # May 1st: Billing run
    may1 = Time.zone.parse('2024-05-1')
    travel_to(may1) do
      perform_billing
      expect(organization.invoices.count).to eq(3)
      expect(partner.invoices.count).to eq(1)
      partner_invoice = partner.invoices.first
      expect(partner_invoice.self_billed).to eq(true)
      organization_invoices = customers.map(&:invoices).flatten
      expect(organization_invoices.map(&:self_billed).uniq).to eq([false])
      expect(organization_invoices.map do |inv|
        inv.number.gsub("#{organization.document_number_prefix}-202405-", '')
      end.uniq.sort).to eq(['001', '002'])
    end

  end
end
