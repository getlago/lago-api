# frozen_string_literal: true

require 'rails_helper'

describe 'Terminate Pay in Advance Scenarios', :scenarios, type: :request do
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

  it 'creates expected credit note and invoice' do
    ### 8 Feb: Create and terminate subscription
    feb8 = DateTime.new(2023, 2, 8)

    travel_to(feb8) do
      expect {
        create_subscription(
          {
            external_customer_id: customer.external_id,
            external_id: customer.external_id,
            plan_code: plan.code
          },
        )
      }.to change(Invoice, :count).by(1)

      subscription = customer.subscriptions.find_by(external_id: customer.external_id)
      sub_invoice = subscription.invoices.first
      expect(sub_invoice.total_amount_cents).to eq(4500) # 60 / 28 * 21

      expect {
        terminate_subscription(subscription)
      }.to change { subscription.reload.status }.from('active').to('terminated')
        .and change { subscription.invoices.count }.from(1).to(2)
        .and change { sub_invoice.reload.credit_notes.count }.from(0).to(1)

      term_invoice = subscription.invoices.order(sequential_id: :desc).first
      expect(term_invoice.total_amount_cents).to eq(0)

      credit_note = sub_invoice.credit_notes.first
      expect(credit_note.total_amount_cents).to eq(4286) # 60.0 / 28 * 20
    end
  end

  context 'when customer is in UTC+ timezone' do
    let(:customer) { create(:customer, organization:, timezone: 'Asia/Tokyo') }

    it 'creates expected credit note and invoice' do
      ### 8 Feb: Create and terminate subscription
      feb8 = DateTime.new(2023, 2, 8)

      travel_to(feb8) do
        expect {
          create_subscription(
            {
              external_customer_id: customer.external_id,
              external_id: customer.external_id,
              plan_code: plan.code
            },
          )
        }.to change(Invoice, :count).by(1)

        subscription = customer.subscriptions.find_by(external_id: customer.external_id)
        sub_invoice = subscription.invoices.first
        expect(sub_invoice.total_amount_cents).to eq(4500) # 60 / 28 * 21

        expect {
          terminate_subscription(subscription)
        }.to change { subscription.reload.status }.from('active').to('terminated')
          .and change { subscription.invoices.count }.from(1).to(2)
          .and change { sub_invoice.reload.credit_notes.count }.from(0).to(1)

        term_invoice = subscription.invoices.order(sequential_id: :desc).first
        expect(term_invoice.total_amount_cents).to eq(0)

        credit_note = sub_invoice.credit_notes.first
        expect(credit_note.total_amount_cents).to eq(4286) # 60.0 / 28 * 20
      end
    end
  end

  context 'when customer is in UTC- timezone' do
    let(:customer) { create(:customer, organization:, timezone: 'America/Los_Angeles') }

    it 'creates expected credit note and invoice' do
      ### 8 Feb: Create and terminate subscription
      feb8 = DateTime.new(2023, 2, 8)

      travel_to(feb8) do
        expect {
          create_subscription(
            {
              external_customer_id: customer.external_id,
              external_id: customer.external_id,
              plan_code: plan.code
            },
          )
        }.to change(Invoice, :count).by(1)

        subscription = customer.subscriptions.find_by(external_id: customer.external_id)
        sub_invoice = subscription.invoices.first
        expect(sub_invoice.total_amount_cents).to eq(4715) # 60 / 28 * 22

        expect {
          terminate_subscription(subscription)
        }.to change { subscription.reload.status }.from('active').to('terminated')
          .and change { subscription.invoices.count }.from(1).to(2)
          .and change { sub_invoice.reload.credit_notes.count }.from(0).to(1)

        term_invoice = subscription.invoices.order(sequential_id: :desc).first
        expect(term_invoice.total_amount_cents).to eq(0)

        credit_note = sub_invoice.credit_notes.first
        expect(credit_note.total_amount_cents).to eq(4500) # 3750 + (3750 * 20 / 100)
      end
    end
  end

  context 'when subscription billing is anniversary' do
    it 'creates expected credit note and invoice' do
      ### 8 Feb: Create and terminate subscription
      feb8 = DateTime.new(2023, 2, 8)

      travel_to(feb8) do
        expect {
          create_subscription(
            {
              external_customer_id: customer.external_id,
              external_id: customer.external_id,
              plan_code: plan.code,
              billing_time: 'anniversary'
            },
          )
        }.to change(Invoice, :count).by(1)

        subscription = customer.subscriptions.find_by(external_id: customer.external_id)
        sub_invoice = subscription.invoices.first
        expect(sub_invoice.total_amount_cents).to eq(6000) # Full period is billed

        expect {
          terminate_subscription(subscription)
        }.to change { subscription.reload.status }.from('active').to('terminated')
          .and change { subscription.invoices.count }.from(1).to(2)
          .and change { sub_invoice.reload.credit_notes.count }.from(0).to(1)

        term_invoice = subscription.invoices.order(sequential_id: :desc).first
        expect(term_invoice.total_amount_cents).to eq(0)

        credit_note = sub_invoice.credit_notes.first
        expect(credit_note.total_amount_cents).to eq(5786)
      end
    end

    context 'when customer is in UTC+ timezone' do
      let(:customer) { create(:customer, organization:, timezone: 'Asia/Tokyo') }

      it 'creates expected credit note and invoice' do
        ### 8 Feb: Create and terminate subscription
        feb8 = DateTime.new(2023, 2, 8)

        travel_to(feb8) do
          expect {
            create_subscription(
              {
                external_customer_id: customer.external_id,
                external_id: customer.external_id,
                plan_code: plan.code,
                billing_time: 'anniversary'
              },
            )
          }.to change(Invoice, :count).by(1)

          subscription = customer.subscriptions.find_by(external_id: customer.external_id)
          sub_invoice = subscription.invoices.first
          expect(sub_invoice.total_amount_cents).to eq(6000) # Full period is billed

          expect {
            terminate_subscription(subscription)
          }.to change { subscription.reload.status }.from('active').to('terminated')
            .and change { subscription.invoices.count }.from(1).to(2)
            .and change { sub_invoice.reload.credit_notes.count }.from(0).to(1)

          term_invoice = subscription.invoices.order(sequential_id: :desc).first
          expect(term_invoice.total_amount_cents).to eq(0)

          credit_note = sub_invoice.credit_notes.first
          expect(credit_note.total_amount_cents).to eq(5786)
        end
      end
    end

    context 'when customer is in UTC- timezone' do
      let(:customer) { create(:customer, organization:, timezone: 'America/Los_Angeles') }

      it 'creates expected credit note and invoice' do
        ### 8 Feb: Create and terminate subscription
        feb8 = DateTime.new(2023, 2, 8)

        travel_to(feb8) do
          expect {
            create_subscription(
              {
                external_customer_id: customer.external_id,
                external_id: customer.external_id,
                plan_code: plan.code,
                billing_time: 'anniversary'
              },
            )
          }.to change(Invoice, :count).by(1)

          subscription = customer.subscriptions.find_by(external_id: customer.external_id)
          sub_invoice = subscription.invoices.first
          expect(sub_invoice.total_amount_cents).to eq(6000) # Full period is billed

          expect {
            terminate_subscription(subscription)
          }.to change { subscription.reload.status }.from('active').to('terminated')
            .and change { subscription.invoices.count }.from(1).to(2)
            .and change { sub_invoice.reload.credit_notes.count }.from(0).to(1)

          term_invoice = subscription.invoices.order(sequential_id: :desc).first
          expect(term_invoice.total_amount_cents).to eq(0)

          credit_note = sub_invoice.credit_notes.first
          expect(credit_note.total_amount_cents).to eq(5786)
        end
      end
    end
  end
end
