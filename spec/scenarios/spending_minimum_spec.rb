# frozen_string_literal: true

require 'rails_helper'

describe 'Spending Minimum Scenarios', :scenarios, type: :request do
  let(:organization) { create(:organization, webhook_url: nil) }
  let(:customer) { create(:customer, organization:) }
  let(:tax) { create(:tax, organization:, rate: 20) }
  let(:plan) { create(:plan, pay_in_advance: true, organization:, amount_cents: 5000) }
  let(:metric) { create(:billable_metric, organization:) }
  let(:pdf_generator) { instance_double(Utils::PdfGenerator) }
  let(:pdf_file) { StringIO.new(File.read(Rails.root.join('spec/fixtures/blank.pdf'))) }
  let(:pdf_result) { OpenStruct.new(io: pdf_file) }

  before do
    tax

    allow(Utils::PdfGenerator).to receive(:new)
      .and_return(pdf_generator)
    allow(pdf_generator).to receive(:call)
      .and_return(pdf_result)
  end

  context 'when invoice grace period' do
    let(:customer) { create(:customer, organization:, invoice_grace_period: 3) }

    it 'creates expected credit note and invoice' do
      ### 8 Jan: Create subscription
      travel_to(DateTime.new(2023, 1, 8, 8)) do
        expect {
          create_subscription(
            {
              external_customer_id: customer.external_id,
              external_id: customer.external_id,
              plan_code: plan.code,
            },
          )
        }.to change(Invoice, :count).by(1)

        create(
          :standard_charge,
          plan:,
          billable_metric: metric,
          properties: { amount: '8' },
          min_amount_cents: 1000,
        )
      end

      subscription = customer.subscriptions.find_by(external_id: customer.external_id)
      sub_invoice = subscription.invoices.first
      expect(sub_invoice.total_amount_cents).to eq(4645) # 60 / 31 * 24

      ### 25 Feb: Create event and Terminate subscription
      travel_to(DateTime.new(2023, 2, 25, 6)) do
        create_event(
          {
            code: metric.code,
            transaction_id: SecureRandom.uuid,
            external_customer_id: customer.external_id,
          },
        )

        expect {
          terminate_subscription(subscription)
        }.to change { subscription.reload.status }.from('active').to('terminated')
          .and change { subscription.invoices.count }.from(1).to(2)

        term_invoice = subscription.invoices.order(sequential_id: :desc).first
        expect(term_invoice).to be_draft

        expect(term_invoice.fees.count).to eq(2)
        usage_fee = term_invoice.fees.where(true_up_parent_fee_id: nil).first
        true_up_fee = usage_fee.true_up_fee

        expect(usage_fee).to have_attributes(
          amount_cents: 800,
          taxes_amount_cents: 160,
          units: 1,
        )

        # True up fee is pro-rated for 25/28 days.
        expect(true_up_fee).to have_attributes(
          amount_cents: 92, # (1000 / 28.0 * 25 - 800).floor
          taxes_amount_cents: 18,
          units: 1,
        )

        expect(term_invoice).to have_attributes(
          fees_amount_cents: 892,
          taxes_amount_cents: 178,
          credit_notes_amount_cents: 0,
          total_amount_cents: 1070,
        )

        # Refresh pay in advance invoice
        expect {
          refresh_invoice(sub_invoice)
        }.not_to change { sub_invoice.reload.total_amount_cents }

        credit_note = sub_invoice.credit_notes.first
        expect(credit_note).to be_draft
        expect(credit_note.reload.total_amount_cents).to eq(643)

        # Refresh termination invoice
        expect {
          refresh_invoice(term_invoice)
        }.not_to change { term_invoice.reload.total_amount_cents }

        # Finalize pay in advance invoice
        expect {
          finalize_invoice(sub_invoice)
        }.to change { sub_invoice.reload.status }.from('draft').to('finalized')
          .and change { credit_note.reload.status }.from('draft').to('finalized')

        # Finalize termination invoice
        expect {
          finalize_invoice(term_invoice)
        }.to change { term_invoice.reload.status }.from('draft').to('finalized')

        credit_note = sub_invoice.credit_notes.first
        expect(credit_note.total_amount_cents).to eq(643) # 60.0 / 28 * 3

        expect(term_invoice).to have_attributes(
          fees_amount_cents: 892,
          taxes_amount_cents: 178,
          credit_notes_amount_cents: 643,
          total_amount_cents: 427, # 892 + 178 - 643
        )
      end
    end
  end

  context 'when dimensions' do
    let(:europe) do
      create(:group, billable_metric_id: metric.id, key: 'region', value: 'europe')
    end

    let(:usa) do
      create(:group, billable_metric_id: metric.id, key: 'region', value: 'usa')
    end

    it 'creates expected credit note and invoice' do
      ### 8 Jan: Create subscription
      travel_to(DateTime.new(2023, 1, 8)) do
        expect {
          create_subscription(
            {
              external_customer_id: customer.external_id,
              external_id: customer.external_id,
              plan_code: plan.code,
            },
          )
        }.to change(Invoice, :count).by(1)

        create(
          :standard_charge,
          plan:,
          billable_metric: metric,
          group_properties: [
            build(
              :group_property,
              group: europe,
              values: {
                amount: '20',
                amount_currency: 'EUR',
              },
            ),
            build(
              :group_property,
              group: usa,
              values: {
                amount: '50',
                amount_currency: 'EUR',
              },
            ),
          ],
          min_amount_cents: 10_000,
        )
      end

      subscription = customer.subscriptions.find_by(external_id: customer.external_id)
      sub_invoice = subscription.invoices.first
      expect(sub_invoice.total_amount_cents).to eq(4645) # 60 / 31 * 24

      ### 25 Feb: Create event and Terminate subscription
      travel_to(DateTime.new(2023, 2, 25, 8)) do
        create_event(
          {
            code: metric.code,
            transaction_id: SecureRandom.uuid,
            external_customer_id: customer.external_id,
            properties: {
              region: 'usa',
            },
          },
        )

        create_event(
          {
            code: metric.code,
            transaction_id: SecureRandom.uuid,
            external_customer_id: customer.external_id,
            properties: {
              region: 'europe',
            },
          },
        )

        expect {
          terminate_subscription(subscription)
        }.to change { subscription.reload.status }.from('active').to('terminated')
          .and change { subscription.invoices.count }.from(1).to(2)

        term_invoice = subscription.invoices.order(sequential_id: :desc).first
        expect(term_invoice).to be_finalized
        expect(term_invoice.fees.count).to eq(3)

        usage_fees = term_invoice.fees.where(true_up_parent_fee_id: nil)
        expect(usage_fees.count).to eq(2)
        expect(usage_fees.pluck(:amount_cents)).to contain_exactly(2000, 5000)

        true_up_fee = term_invoice.fees.where.not(true_up_parent_fee_id: nil).first
        # True up fee is pro-rated for 25/28 days.
        expect(true_up_fee).to have_attributes(
          amount_cents: 1928, # (10000 / 28.0 * 25 - 2000 - 5000).floor
          taxes_amount_cents: 386,
          units: 1,
        )

        expect(term_invoice).to have_attributes(
          fees_amount_cents: 8928, # 1928 + 2000 + 5000
          taxes_amount_cents: 1786,
          credit_notes_amount_cents: 643,
          total_amount_cents: 10_071,
        )
      end
    end
  end
end
