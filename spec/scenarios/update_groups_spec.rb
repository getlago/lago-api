# frozen_string_literal: true

require 'rails_helper'

describe 'Update Groups Scenarios', :scenarios, type: :request do
  let(:organization) { create(:organization, webhook_url: nil, invoice_grace_period: 1) }

  let(:pdf_generator) { instance_double(Utils::PdfGenerator) }
  let(:pdf_file) { StringIO.new(File.read(Rails.root.join('spec/fixtures/blank.pdf'))) }
  let(:pdf_result) { OpenStruct.new(io: pdf_file) }

  before do
    organization

    allow(Utils::PdfGenerator).to receive(:new).and_return(pdf_generator)
    allow(pdf_generator).to receive(:call).and_return(pdf_result)
  end

  around { |test| lago_premium!(&test) }

  context 'when two dimensions to one dimension' do
    it 'updates groups and draft invoices' do
      travel_to(DateTime.new(2023, 1, 1)) do
        create_or_update_customer(external_id: 'customer-1')
        create_metric(
          name: 'Cards',
          code: 'cards',
          aggregation_type: 'count_agg',
          group: {
            key: 'cloud',
            values: [
              { name: 'AWS', key: 'region', values: %w[usa europe] },
              { name: 'Google', key: 'region', values: ['usa'] },
            ],
          },
        )
        cards = organization.billable_metrics.find_by(code: 'cards')

        create_plan(
          {
            name: 'P1',
            code: 'plan_code',
            interval: 'monthly',
            amount_cents: 10_000,
            amount_currency: 'EUR',
            pay_in_advance: false,
            charges: [
              {
                billable_metric_id: cards.id,
                charge_model: 'standard',
                properties: { amount: '30' },
              },
            ],
          },
        )
        plan = organization.plans.find_by(code: 'plan_code')

        create_subscription(
          {
            external_customer_id: 'customer-1',
            external_id: 'sub_external_id',
            plan_code: plan.code,
          },
        )

        create_event(
          {
            code: cards.code,
            transaction_id: SecureRandom.uuid,
            external_subscription_id: 'sub_external_id',
            properties: { cloud: 'AWS', region: 'europe' },
          },
        )

        create_event(
          {
            code: cards.code,
            transaction_id: SecureRandom.uuid,
            external_subscription_id: 'sub_external_id',
            properties: { cloud: 'Google', region: 'usa' },
          },
        )

        create_event(
          {
            code: cards.code,
            transaction_id: SecureRandom.uuid,
            external_subscription_id: 'sub_external_id',
            properties: { region: 'usa' },
          },
        )

        expect(cards.groups.parents.pluck(:value)).to contain_exactly('AWS', 'Google')
        expect(cards.groups.children.pluck(:value)).to contain_exactly('usa', 'europe', 'usa')
      end

      travel_to(DateTime.new(2023, 2, 1)) do
        perform_billing

        customer = organization.customers.find_by(external_id: 'customer-1')
        invoice = customer.invoices.first
        expect(invoice.total_amount_cents).to eq(16_000)

        cards = organization.billable_metrics.find_by(code: 'cards')
        update_metric(
          cards,
          group: {
            key: 'region',
            values: %w[usa europe],
          },
        )
        perform_invoices_refresh

        expect(cards.groups.pluck(:value)).to contain_exactly('usa', 'europe')
        expect(invoice.reload.total_amount_cents).to eq(19_000)
      end
    end
  end

  context 'when one dimension to two dimensions' do
    it 'updates groups and draft invoices' do
      travel_to(DateTime.new(2023, 1, 1)) do
        create_or_update_customer(external_id: 'customer-1')
        create_metric(
          name: 'Cards',
          code: 'cards',
          aggregation_type: 'count_agg',
          group: {
            key: 'cloud',
            values: %w[aws google azure],
          },
        )
        cards = organization.billable_metrics.find_by(code: 'cards')

        create_plan(
          {
            name: 'P1',
            code: 'plan_code',
            interval: 'monthly',
            amount_cents: 10_000,
            amount_currency: 'EUR',
            pay_in_advance: false,
            charges: [
              {
                billable_metric_id: cards.id,
                charge_model: 'standard',
                properties: { amount: '30' },
                group_properties: [
                  {
                    group_id: cards.groups.find_by(value: 'aws').id,
                    values: { amount: '10' },
                  },
                ],
              },
            ],
          },
        )
        plan = organization.plans.find_by(code: 'plan_code')

        create_subscription(
          {
            external_customer_id: 'customer-1',
            external_id: 'sub_external_id',
            plan_code: plan.code,
          },
        )

        create_event(
          {
            code: cards.code,
            transaction_id: SecureRandom.uuid,
            external_subscription_id: 'sub_external_id',
            properties: { cloud: 'aws' },
          },
        )

        create_event(
          {
            code: cards.code,
            transaction_id: SecureRandom.uuid,
            external_subscription_id: 'sub_external_id',
            properties: { cloud: 'google' },
          },
        )

        create_event(
          {
            code: cards.code,
            transaction_id: SecureRandom.uuid,
            external_subscription_id: 'sub_external_id',
            properties: { country: 'usa', cloud: 'aws' },
          },
        )

        expect(cards.groups.pluck(:value)).to contain_exactly('aws', 'google', 'azure')
      end

      travel_to(DateTime.new(2023, 2, 1)) do
        perform_billing

        customer = organization.customers.find_by(external_id: 'customer-1')
        invoice = customer.invoices.first
        expect(invoice.total_amount_cents).to eq(15_000)

        cards = organization.billable_metrics.find_by(code: 'cards')
        update_metric(
          cards,
          group: {
            key: 'cloud',
            values: [
              { name: 'azure', key: 'country', values: %w[usa france] },
              { name: 'google', key: 'country', values: ['usa'] },
            ],
          },
        )
        perform_invoices_refresh

        expect(cards.groups.parents.pluck(:value)).to contain_exactly('azure', 'google')
        expect(cards.groups.children.pluck(:value)).to contain_exactly('usa', 'france', 'usa')
        expect(cards.charges.first.group_properties.count).to eq(0)
        expect(cards.charges.first.filters.count).to eq(5)
        expect(invoice.reload.total_amount_cents).to eq(19_000)
      end
    end
  end
end
