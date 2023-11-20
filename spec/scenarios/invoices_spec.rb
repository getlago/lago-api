# frozen_string_literal: true

require 'rails_helper'

describe 'Invoices Scenarios', :scenarios, type: :request do
  let(:organization) { create(:organization, webhook_url: nil) }
  let(:tax) { create(:tax, organization:, rate: 20) }

  before { tax }

  context 'when timezone is negative and not the same day as UTC' do
    let(:organization) { create(:organization, webhook_url: nil) }
    let(:tax) { create(:tax, organization:, rate: 0) }
    let(:customer) { create(:customer, organization:, timezone: 'America/Denver') } # UTC-6
    let(:plan) { create(:plan, organization:, amount_cents: 700, pay_in_advance: true, interval: 'weekly') }

    it 'creates an invoice for the expected period' do
      travel_to(DateTime.new(2023, 6, 16, 5)) do
        create_subscription(
          {
            external_customer_id: customer.external_id,
            external_id: customer.external_id,
            plan_code: plan.code,
          },
        )

        subscription = customer.subscriptions.first
        invoice = subscription.invoices.first
        expect(invoice.total_amount_cents).to eq(400) # 4 days
      end
    end
  end

  context 'when timezone is negative but same day as UTC' do
    let(:organization) { create(:organization, webhook_url: nil) }
    let(:tax) { create(:tax, organization:, rate: 0) }
    let(:customer) { create(:customer, organization:, timezone: 'America/Halifax') } # UTC-3
    let(:plan) { create(:plan, organization:, amount_cents: 700, pay_in_advance: true, interval: 'weekly') }

    it 'creates an invoice for the expected period' do
      travel_to(DateTime.new(2023, 6, 16, 5)) do
        create_subscription(
          {
            external_customer_id: customer.external_id,
            external_id: customer.external_id,
            plan_code: plan.code,
          },
        )

        subscription = customer.subscriptions.first
        invoice = subscription.invoices.first
        expect(invoice.total_amount_cents).to eq(300) # 3 days
      end
    end
  end

  context 'when timezone is positive but same day as UTC' do
    let(:organization) { create(:organization, webhook_url: nil) }
    let(:tax) { create(:tax, organization:, rate: 0) }
    let(:customer) { create(:customer, organization:, timezone: 'Europe/Paris') } # UTC+2
    let(:plan) { create(:plan, organization:, amount_cents: 700, pay_in_advance: true, interval: 'weekly') }

    it 'creates an invoice for the expected period' do
      travel_to(DateTime.new(2023, 6, 16, 20)) do
        create_subscription(
          {
            external_customer_id: customer.external_id,
            external_id: customer.external_id,
            plan_code: plan.code,
          },
        )

        subscription = customer.subscriptions.first
        invoice = subscription.invoices.first
        expect(invoice.total_amount_cents).to eq(300) # 3 days
      end
    end
  end

  context 'when timezone is positive and not the same day as UTC' do
    let(:organization) { create(:organization, webhook_url: nil) }
    let(:tax) { create(:tax, organization:, rate: 0) }
    let(:customer) { create(:customer, organization:, timezone: 'Asia/Karachi') } # UTC+5
    let(:plan) { create(:plan, organization:, amount_cents: 700, pay_in_advance: true, interval: 'weekly') }

    it 'creates an invoice for the expected period' do
      travel_to(DateTime.new(2023, 6, 16, 20)) do
        create_subscription(
          {
            external_customer_id: customer.external_id,
            external_id: customer.external_id,
            plan_code: plan.code,
          },
        )

        subscription = customer.subscriptions.first
        invoice = subscription.invoices.first
        expect(invoice.total_amount_cents).to eq(200) # 2 days
      end
    end
  end

  context 'when subscription is terminated with a grace period' do
    let(:customer) { create(:customer, organization:, invoice_grace_period: 3) }
    let(:plan) { create(:plan, organization:, amount_cents: 1000) }
    let(:metric) { create(:billable_metric, organization:) }

    it 'does not update the invoice amount on refresh' do
      ### 15 Dec: Create subscription + charge.
      dec15 = DateTime.new(2022, 12, 15)

      travel_to(dec15) do
        create_subscription(
          {
            external_customer_id: customer.external_id,
            external_id: customer.external_id,
            plan_code: plan.code,
          },
        )

        create(:standard_charge, plan:, billable_metric: metric, properties: { amount: '3' })
      end

      subscription = customer.subscriptions.first

      ### 20 Dec: Terminate subscription + refresh.
      dec20 = DateTime.parse('2022-12-20 06:00:00')

      travel_to(dec20) do
        expect {
          terminate_subscription(subscription)
        }.to change { subscription.reload.status }.from('active').to('terminated')
          .and change { subscription.invoices.count }.from(0).to(1)

        invoice = subscription.invoices.first
        expect(invoice.total_amount_cents).to eq(233) # 12 / 31 * 6

        # Refresh invoice
        expect {
          refresh_invoice(invoice)
        }.not_to change { invoice.reload.total_amount_cents }
      end
    end
  end

  context 'when pay in arrear subscription with recurring charges is terminated' do
    let(:customer) { create(:customer, organization:) }
    let(:plan) { create(:plan, organization:, amount_cents: 1000) }
    let(:metric) do
      create(:billable_metric, organization:, aggregation_type: 'sum_agg', recurring: true, field_name: 'amount')
    end

    it 'does bill the charges' do
      ### 15 Dec: Create subscription + charge.
      dec15 = DateTime.new(2022, 12, 15)

      travel_to(dec15) do
        create(
          :standard_charge,
          plan:,
          billable_metric: metric,
          pay_in_advance: false,
          prorated: false,
          properties: { amount: '3' },
        )

        create_subscription(
          {
            external_customer_id: customer.external_id,
            external_id: customer.external_id,
            plan_code: plan.code,
          },
        )
      end

      subscription = customer.subscriptions.first

      ### 20 Dec: Terminate subscription + refresh.
      dec20 = DateTime.parse('2022-12-20 06:00:00')

      travel_to(dec20) do
        expect {
          terminate_subscription(subscription)
        }.to change { subscription.reload.status }.from('active').to('terminated')
          .and change { subscription.invoices.count }.from(0).to(1)

        invoice = subscription.invoices.first
        expect(invoice.fees.charge_kind.count).to eq(1)
      end
    end
  end

  context 'when pay in arrear subscription with recurring and prorated charges is terminated' do
    let(:customer) { create(:customer, organization:) }
    let(:plan) { create(:plan, organization:, amount_cents: 1000) }
    let(:metric) do
      create(:billable_metric, organization:, aggregation_type: 'sum_agg', recurring: true, field_name: 'amount')
    end

    it 'does bill the charges' do
      ### 15 Dec: Create subscription + charge.
      dec15 = DateTime.new(2022, 12, 15)

      travel_to(dec15) do
        create(
          :standard_charge,
          plan:,
          billable_metric: metric,
          pay_in_advance: false,
          prorated: true,
          properties: { amount: '3' },
        )

        create_subscription(
          {
            external_customer_id: customer.external_id,
            external_id: customer.external_id,
            plan_code: plan.code,
          },
        )
      end

      subscription = customer.subscriptions.first

      ### 20 Dec: Terminate subscription + refresh.
      dec20 = DateTime.parse('2022-12-20 06:00:00')

      travel_to(dec20) do
        expect {
          terminate_subscription(subscription)
        }.to change { subscription.reload.status }.from('active').to('terminated')
          .and change { subscription.invoices.count }.from(0).to(1)

        invoice = subscription.invoices.first
        expect(invoice.fees.charge_kind.count).to eq(1)
      end
    end
  end

  context 'when pay in arrear subscription with recurring charges is upgraded and new plan does not contain same BM' do
    let(:customer) { create(:customer, organization:) }
    let(:plan) { create(:plan, organization:, amount_cents: 1000) }
    let(:plan_new) { create(:plan, organization:, amount_cents: 2000) }
    let(:metric) do
      create(:billable_metric, organization:, aggregation_type: 'sum_agg', recurring: true, field_name: 'amount')
    end

    it 'does bill the charges' do
      ### 15 Dec: Create subscription + charge.
      dec15 = DateTime.new(2022, 12, 15)

      travel_to(dec15) do
        create(
          :standard_charge,
          plan:,
          billable_metric: metric,
          pay_in_advance: false,
          prorated: false,
          properties: { amount: '3' },
        )

        create_subscription(
          {
            external_customer_id: customer.external_id,
            external_id: customer.external_id,
            plan_code: plan.code,
          },
        )
      end

      subscription = customer.subscriptions.first

      ### 20 Dec: Upgrade subscription
      dec20 = DateTime.parse('2022-12-20 06:00:00')

      travel_to(dec20) do
        expect {
          create_subscription(
            {
              external_customer_id: customer.external_id,
              external_id: customer.external_id,
              plan_code: plan_new.code,
            },
          )
        }.to change { subscription.reload.status }.from('active').to('terminated')
          .and change { subscription.invoices.count }.from(0).to(1)

        invoice = subscription.invoices.first
        expect(invoice.fees.charge_kind.count).to eq(1)
      end
    end
  end

  context 'when pay in arrear subscription with recurring charges is upgraded and new plan contains same BM' do
    let(:customer) { create(:customer, organization:) }
    let(:plan) { create(:plan, organization:, amount_cents: 1000) }
    let(:plan_new) { create(:plan, organization:, amount_cents: 2000) }
    let(:metric) do
      create(:billable_metric, organization:, aggregation_type: 'sum_agg', recurring: true, field_name: 'amount')
    end

    it 'does not bill the charges' do
      ### 15 Dec: Create subscription + charge.
      dec15 = DateTime.new(2022, 12, 15)

      travel_to(dec15) do
        create(
          :standard_charge,
          plan:,
          billable_metric: metric,
          pay_in_advance: false,
          prorated: false,
          properties: { amount: '3' },
        )

        create_subscription(
          {
            external_customer_id: customer.external_id,
            external_id: customer.external_id,
            plan_code: plan.code,
          },
        )
      end

      subscription = customer.subscriptions.first

      ### 20 Dec: Upgrade subscription
      dec20 = DateTime.parse('2022-12-20 06:00:00')

      travel_to(dec20) do
        create(
          :standard_charge,
          plan: plan_new,
          billable_metric: metric,
          pay_in_advance: false,
          prorated: false,
          properties: { amount: '3' },
        )

        expect {
          create_subscription(
            {
              external_customer_id: customer.external_id,
              external_id: customer.external_id,
              plan_code: plan_new.code,
            },
          )
        }.to change { subscription.reload.status }.from('active').to('terminated')
          .and change { subscription.invoices.count }.from(0).to(1)

        invoice = subscription.invoices.first
        expect(invoice.fees.charge_kind.count).to eq(0)
      end
    end
  end

  context 'when pay in advance subscription with recurring and prorated charges is terminated' do
    let(:customer) { create(:customer, organization:) }
    let(:plan) { create(:plan, organization:, amount_cents: 1000) }
    let(:metric) do
      create(:billable_metric, organization:, aggregation_type: 'sum_agg', recurring: true, field_name: 'amount')
    end

    it 'does not bill the charges' do
      ### 15 Dec: Create subscription + charge.
      dec15 = DateTime.new(2022, 12, 15)

      travel_to(dec15) do
        create(
          :standard_charge,
          plan:,
          billable_metric: metric,
          pay_in_advance: true,
          prorated: true,
          properties: { amount: '3' },
        )

        create_subscription(
          {
            external_customer_id: customer.external_id,
            external_id: customer.external_id,
            plan_code: plan.code,
          },
        )
      end

      subscription = customer.subscriptions.first

      ### 20 Dec: Terminate subscription + refresh.
      dec20 = DateTime.parse('2022-12-20 06:00:00')

      travel_to(dec20) do
        expect {
          terminate_subscription(subscription)
        }.to change { subscription.reload.status }.from('active').to('terminated')
          .and change { subscription.invoices.count }.from(0).to(1)

        invoice = subscription.invoices.first
        expect(invoice.fees.charge_kind.count).to eq(0)
      end
    end
  end

  context 'when invoice is paid in advance and grace period' do
    let(:customer) { create(:customer, organization:, invoice_grace_period: 3) }
    let(:plan) { create(:plan, pay_in_advance: true, organization:, amount_cents: 1000) }
    let(:metric) { create(:billable_metric, organization:) }

    it 'terminates the pay in advance subscription with credit note lesser than amount' do
      ### 15 Dec: Create subscription + charge.
      dec15 = DateTime.new(2022, 12, 15)

      travel_to(dec15) do
        create_subscription(
          {
            external_customer_id: customer.external_id,
            external_id: customer.external_id,
            plan_code: plan.code,
          },
        )

        create(:standard_charge, plan:, billable_metric: metric, properties: { amount: '3' })
      end

      subscription_invoice = Invoice.draft.first
      subscription = subscription_invoice.subscriptions.first
      expect(subscription_invoice.total_amount_cents).to eq(658) # 17 days - From 15th Dec. to 31st Dec.

      ### 17 Dec: Create event + refresh.
      travel_to(DateTime.new(2022, 12, 17)) do
        create(:event, external_subscription_id: subscription.external_id, code: metric.code)
        create(:event, external_subscription_id: subscription.external_id, code: metric.code)

        expect {
          refresh_invoice(subscription_invoice)
        }.not_to change { subscription_invoice.reload.total_amount_cents }
      end

      ### 20 Dec: Terminate subscription + refresh.
      dec20 = DateTime.new(2022, 12, 20)

      travel_to(dec20) do
        expect {
          terminate_subscription(subscription)
        }.to change { subscription.reload.status }.from('active').to('terminated')
          .and change { subscription_invoice.reload.credit_notes.count }.from(0).to(1)
          .and change { subscription.invoices.count }.from(1).to(2)

        # Draft credit note is created (31 - 20) * 548 / 17.0 * 1.2 = 425.5 rounded at 426
        credit_note = subscription_invoice.credit_notes.first
        expect(credit_note).to be_draft
        expect(credit_note.credit_amount_cents).to eq(426)
        expect(credit_note.balance_amount_cents).to eq(426)
        expect(credit_note.total_amount_cents).to eq(426)

        # Invoice for termination is created
        termination_invoice = subscription.invoices.order(created_at: :desc).first

        # Total amount does not reflect the credit note as it's not finalized.
        expect(termination_invoice.total_amount_cents).to eq(720)
        expect(termination_invoice.credits.count).to eq(0)
        expect(termination_invoice.credit_notes.count).to eq(0)

        # Refresh pay in advance invoice
        expect {
          refresh_invoice(subscription_invoice)
        }.not_to change { subscription_invoice.reload.total_amount_cents }
        expect(credit_note.reload.total_amount_cents).to eq(426)

        # Refresh termination invoice
        expect {
          refresh_invoice(termination_invoice)
        }.not_to change { termination_invoice.reload.total_amount_cents }

        # Finalize pay in advance invoice
        expect {
          finalize_invoice(subscription_invoice)
        }.to change { subscription_invoice.reload.status }.from('draft').to('finalized')
          .and change { credit_note.reload.status }.from('draft').to('finalized')

        expect(subscription_invoice.total_amount_cents).to eq(658)

        # Finalize termination invoice
        expect {
          finalize_invoice(termination_invoice)
        }.to change { termination_invoice.reload.status }.from('draft').to('finalized')

        # Total amount should reflect the credit note 720 - 426
        expect(termination_invoice.total_amount_cents).to eq(294)
      end
    end

    it 'terminates the pay in advance subscription with credit note greater than amount' do
      ### 15 Dec: Create subscription + charge.
      dec15 = DateTime.new(2022, 12, 15)

      travel_to(dec15) do
        create_subscription(
          {
            external_customer_id: customer.external_id,
            external_id: customer.external_id,
            plan_code: plan.code,
          },
        )

        create(:standard_charge, plan:, billable_metric: metric, properties: { amount: '1' })
      end

      subscription_invoice = Invoice.draft.first
      subscription = subscription_invoice.subscriptions.first
      expect(subscription_invoice.total_amount_cents).to eq(658) # 17 days - From 15th Dec. to 31st Dec.

      ### 17 Dec: Create event + refresh.
      travel_to(DateTime.new(2022, 12, 17)) do
        create(:event, external_subscription_id: subscription.external_id, code: metric.code)

        expect {
          refresh_invoice(subscription_invoice)
        }.not_to change { subscription_invoice.reload.total_amount_cents }
      end

      ### 20 Dec: Terminate subscription + refresh.
      dec20 = DateTime.new(2022, 12, 20)

      travel_to(dec20) do
        expect {
          terminate_subscription(subscription)
        }.to change { subscription.reload.status }.from('active').to('terminated')
          .and change { subscription_invoice.reload.credit_notes.count }.from(0).to(1)
          .and change { subscription.invoices.count }.from(1).to(2)

        # Credit note is created (31 - 20) * 548 / 17.0 * 1.2 = 425.5 rounded at 426
        credit_note = subscription_invoice.credit_notes.first
        expect(credit_note.credit_amount_cents).to eq(426)
        expect(credit_note.balance_amount_cents).to eq(426)

        # Invoice for termination is created
        termination_invoice = subscription.invoices.order(created_at: :desc).first

        # Total amount does not reflect the credit note as it's not finalized.
        expect(termination_invoice.total_amount_cents).to eq(120)
        expect(termination_invoice.credits.count).to eq(0)
        expect(termination_invoice.credit_notes.count).to eq(0)

        # Refresh pay in advance invoice
        expect {
          refresh_invoice(subscription_invoice)
        }.not_to change { subscription_invoice.reload.total_amount_cents }
        expect(credit_note.reload.credit_amount_cents).to eq(426)

        # Refresh termination invoice
        expect {
          refresh_invoice(termination_invoice)
        }.not_to change { termination_invoice.reload.total_amount_cents }

        # Finalize pay in advance invoice
        expect {
          finalize_invoice(subscription_invoice)
        }.to change { subscription_invoice.reload.status }.from('draft').to('finalized')
          .and change { credit_note.reload.status }.from('draft').to('finalized')

        expect(subscription_invoice.total_amount_cents).to eq(658)

        # Finalize termination invoice
        expect {
          finalize_invoice(termination_invoice)
        }.to change { termination_invoice.reload.status }.from('draft').to('finalized')

        # Total amount should reflect the credit note (120 - 425)
        expect(termination_invoice.total_amount_cents).to eq(0)
      end
    end

    it 'refreshes and finalizes invoices' do
      ### 15 Dec: Create subscription + charge.
      dec15 = DateTime.new(2022, 12, 15)

      travel_to(dec15) do
        create_subscription(
          {
            external_customer_id: customer.external_id,
            external_id: customer.external_id,
            plan_code: plan.code,
          },
        )

        create(:standard_charge, plan:, billable_metric: metric, properties: { amount: '1' })
      end

      invoice = Invoice.draft.first
      subscription = invoice.subscriptions.first
      expect(invoice.total_amount_cents).to eq(658) # 17 days - From 15th Dec. to 31st Dec.

      ### 16 Dec: Create event + refresh.
      travel_to(DateTime.new(2022, 12, 16)) do
        create(:event, external_subscription_id: subscription.external_id, code: metric.code)

        # Paid in advance invoice amount does not change.
        expect {
          refresh_invoice(invoice)
        }.not_to change { invoice.reload.total_amount_cents }
      end

      ### 17 Dec: Create event + refresh.
      travel_to(DateTime.new(2022, 12, 17)) do
        create(:event, external_subscription_id: subscription.external_id, code: metric.code)

        # Paid in advance invoice amount does not change.
        expect {
          refresh_invoice(invoice)
        }.not_to change { invoice.reload.total_amount_cents }
      end

      ### 1 Jan: Billing + refresh + finalize.
      travel_to(DateTime.new(2023, 1, 1)) do
        perform_billing

        expect(subscription.invoices.count).to eq(2)
        new_invoice = subscription.invoices.order(created_at: :desc).first
        expect(new_invoice.total_amount_cents).to eq(1440) # (1000 + 200) * 1.2

        # Create event for Dec 18.
        create(
          :event,
          external_subscription_id: subscription.external_id,
          timestamp: DateTime.new(2022, 12, 18),
          code: metric.code,
        )

        # Paid in advance invoice amount does not change.
        expect {
          refresh_invoice(invoice)
        }.not_to change { invoice.reload.total_amount_cents }

        # Usage invoice amount is updated.
        expect {
          refresh_invoice(new_invoice)
        }.to change { new_invoice.reload.total_amount_cents }.from(1440).to(1560) # (1000 + 200 + 100) * 1.2

        # Finalize invoices.
        expect {
          finalize_invoice(invoice)
        }.to change { invoice.reload.status }.from('draft').to('finalized')

        expect {
          finalize_invoice(new_invoice)
        }.to change { new_invoice.reload.status }.from('draft').to('finalized')

        expect(invoice.total_amount_cents).to eq(658)
        expect(new_invoice.total_amount_cents).to eq(1560)
      end
    end

    context 'when upgrading from pay in arrear to pay in advance plan' do
      let(:pay_in_arrear_plan) { create(:plan, organization:, amount_cents: 1000) }
      let(:pay_in_advance_plan) { create(:plan, organization:, pay_in_advance: true, amount_cents: 1000) }

      it 'creates two draft invoices' do
        create_subscription(
          {
            external_customer_id: customer.external_id,
            external_id: customer.external_id,
            plan_code: pay_in_arrear_plan.code,
          },
        )

        create(:standard_charge, plan:, billable_metric: metric, properties: { amount: '1' })

        # Upgrade to pay in advance plan
        create_subscription(
          {
            external_customer_id: customer.external_id,
            external_id: customer.external_id,
            plan_code: pay_in_advance_plan.code,
          },
        )

        expect(customer.invoices.draft.count).to eq(2)

        pay_in_arrear_subscription = customer.subscriptions.terminated.first
        pay_in_arrear_invoice = pay_in_arrear_subscription.invoices.first

        # Paid in advance invoice amount does not change.
        expect {
          refresh_invoice(pay_in_arrear_invoice)
        }.not_to change { pay_in_arrear_invoice.reload.total_amount_cents }
      end
    end

    context 'when invoice grace period is removed' do
      let(:organization) { create(:organization, webhook_url: nil, invoice_grace_period: 3) }
      let(:plan) { create(:plan, pay_in_advance: true, organization:, amount_cents: 1000) }
      let(:pdf_generator) { instance_double(Utils::PdfGenerator) }
      let(:pdf_file) { StringIO.new(File.read(Rails.root.join('spec/fixtures/blank.pdf'))) }
      let(:pdf_result) { OpenStruct.new(io: pdf_file) }

      around { |test| lago_premium!(&test) }

      before do
        allow(Utils::PdfGenerator).to receive(:new)
          .and_return(pdf_generator)
        allow(pdf_generator).to receive(:call)
          .and_return(pdf_result)
      end

      it 'finalizes draft invoices' do
        create_subscription(
          {
            external_customer_id: customer.external_id,
            external_id: customer.external_id,
            plan_code: plan.code,
          },
        )

        create(:standard_charge, plan:, billable_metric: metric, properties: { amount: '1' })

        invoice = Invoice.draft.first

        params = {
          external_id: customer.external_id,
          billing_configuration: { invoice_grace_period: 0 },
        }

        expect {
          create_or_update_customer(params)
        }.to change { customer.reload.invoice_grace_period }.from(3).to(0)
          .and change { invoice.reload.status }.from('draft').to('finalized')
      end
    end
  end
end
