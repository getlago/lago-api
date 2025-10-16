# frozen_string_literal: true

require "rails_helper"
describe "Billing Monthly Scenarios with all charges types" do

  let(:organization) { create(:organization, webhook_url: nil) }
  let(:timezone) { "UTC" }
  let(:customer) { create(:customer, organization:, timezone:) }
  let(:plan) do
    create(
      :plan,
      organization:,
      amount_cents: 5_000_000,
      interval: "monthly",
      pay_in_advance: false
    )
  end
  let(:billable_metric_metered) do
    create(
      :billable_metric,
      organization:,
      name: "Metered in arrears",
      code: "metered",
      aggregation_type: "sum_agg",
      field_name: "total",
      recurring: false
    )
  end
  let(:billable_metric_recurring) do
    create(
      :billable_metric,
      organization:,
      name: "Recurring",
      code: "recurring",
      aggregation_type: "sum_agg",
      field_name: "total",
      recurring: true
    )
  end
  let(:charge_metered_not_prorated_in_arrears) do
    create(
      :package_charge,
      plan:,
      billable_metric: billable_metric_metered,
      properties: { amount: "100", package_size: 10, free_units: 0 },
      prorated: false,
      pay_in_advance: false
    )
  end
  let(:charge_metered_not_prorated_in_advance) do
    create(
      :package_charge,
      plan:,
      billable_metric: billable_metric_metered,
      properties: { amount: "1000", package_size: 10, free_units: 2 },
      prorated: false,
      pay_in_advance: true
    )
  end
  let(:charge_recurring_prorated_in_arrears) do
    create(
      :charge,
      plan:,
      billable_metric: billable_metric_recurring,
      properties: { amount: "5000" },
      prorated: true,
      pay_in_advance: false
    )
  end
  let(:charge_recurring_prorated_in_advance) do
    create(
      :charge,
      plan:,
      billable_metric: billable_metric_recurring,
      properties: { amount: "50000" },
      prorated: false,
      pay_in_advance: true
    )
  end
  let(:add_on) { create(:add_on)}
  let(:fixed_charge_not_prorated_in_arrears) { create(:fixed_charge, plan:, add_on:, units: 10, properties: { amount: "200" }, prorated: false, pay_in_advance: false) }
  let(:fixed_charge_not_prorated_in_advance) { create(:fixed_charge, plan:, add_on:, units: 10, properties: { amount: "200" }, prorated: false, pay_in_advance: true) }
  let(:fixed_charge_prorated_in_arrears) { create(:fixed_charge, plan:, add_on:, units: 10, properties: { amount: "200" }, prorated: true, pay_in_advance: false) }
  let(:fixed_charge_prorated_in_advance) { create(:fixed_charge, plan:, add_on:, units: 10, properties: { amount: "200" }, prorated: true, pay_in_advance: true) }

  before do
    charge_metered_not_prorated_in_arrears
    charge_metered_not_prorated_in_advance
    charge_recurring_prorated_in_arrears
    charge_recurring_prorated_in_advance
    fixed_charge_not_prorated_in_arrears
    fixed_charge_not_prorated_in_advance
    fixed_charge_prorated_in_arrears
    fixed_charge_prorated_in_advance
  end

  context "with calendar billing" do
    # let's also have here a spec for boundaries that we have on invoice_subscriptions
    let(:billing_time) { "calendar" }
    # february leap year!
    let(:subscription_time) { DateTime.new(2024, 2, 4) }

    it "work the whole year", transaction: false do
      subscription_date = DateTime.new(2024, 2, 4)
      travel_to subscription_date do
        create_subscription(
          {
            external_customer_id: customer.external_id,
            external_id: customer.external_id,
            plan_code: plan.code,
            billing_time:
          }
        )
      end
      subscription = customer.subscriptions.first
      travel_to subscription_date + 10.minutes do
        perform_all_enqueued_jobs
      end
      # we have 1 because we're starting having fixed_charges
      # but it will be empty now
      expect(subscription.reload.invoices.count).to eq(1)
      expect(subscription.invoices.first.total_amount_cents).to eq(0)
      # it immediately creates invoice with pay_in_advance fixed_charges
      # expect(subscription.reload.invoices.count).to eq(1)
      # pay_in_advance_fixed_charges_invoice = subscription.invoices.first
      # this will be a part of another PR
      # expect(pay_in_advance_fixed_charges_invoice.fees.fixed_charge.count).to eq(2)

      # 28th of Feb - before billing, no usage sent for usage charges
      time = DateTime.new(2024, 2, 28)
      travel_to(time) do
        perform_billing
      end
      #old invoice
      expect(subscription.reload.invoices.count).to eq(1)

      time = DateTime.new(2024, 3, 1)
      travel_to(time) do
        perform_billing
      end
      expect(subscription.reload.invoices.count).to eq(2)
      last_invoice = subscription.invoices.order(:created_at).last

      # yet fixed_charge is 0, will be 4...
      expect(last_invoice.fees.fixed_charge.count).to eq(0)
      expect(last_invoice.fees.charge.count).to eq(0)
      expect(last_invoice.fees.subscription.count).to eq(1)
      expect(last_invoice.total_amount_cents).to eq((26.0 / 29 * 5_000_000).ceil)

      # check invoice_subscription
      last_invoice_inv_sub = last_invoice.invoice_subscriptions.first
      expect(last_invoice_inv_sub.from_datetime).to match_datetime("2024-02-04T00:00:00Z")
      expect(last_invoice_inv_sub.to_datetime).to match_datetime("2024-02-29T23:59:59Z")
      expect(last_invoice_inv_sub.charges_from_datetime).to match_datetime("2024-02-04T00:00:00Z")
      expect(last_invoice_inv_sub.charges_to_datetime).to match_datetime("2024-02-29T23:59:59Z")
      expect(last_invoice_inv_sub.fixed_charges_from_datetime).to match_datetime("2024-02-04T00:00:00Z")
      expect(last_invoice_inv_sub.fixed_charges_to_datetime).to match_datetime("2024-02-29T23:59:59Z")
      expect(last_invoice_inv_sub.timestamp).to match_datetime("2024-03-01T00:00:00Z")

      # travel to the middle of month and create events per each charge:
      events_date = DateTime.new(2024, 3, 15)
      travel_to(events_date) do
        [billable_metric_metered, billable_metric_recurring].each do |billable_metric|
          create_event(
            {
              transaction_id: SecureRandom.uuid,
              external_subscription_id: subscription.external_id,
              code: billable_metric.code,
              properties: {
                billable_metric.field_name => 10
              }
            }
          )
        end
        perform_all_enqueued_jobs
      end
      # we should create invoices for received pay_in_advance charges:
      expect(subscription.reload.invoices.count).to eq(4)
      last_invoices = subscription.invoices.order(:created_at).last(2)
      expect(last_invoices.map{|inv| inv.fees.charge.count}.uniq).to eq([1])
      expect(last_invoices.map{|inv| inv.fees.charge.map(&:charge_id)}).to match_array([[charge_metered_not_prorated_in_advance.id], [charge_recurring_prorated_in_advance.id]])
      expect(last_invoices.map{|inv| inv.total_amount_cents}.sort).to match_array([100000, 50000000])

      billing_time = DateTime.new(2024, 4, 1)
      travel_to(billing_time) do
        EventsRecord.connection.commit_db_transaction
        perform_billing
      end
      expect(subscription.reload.invoices.count).to eq(5)
      last_invoice = subscription.invoices.order(:created_at).last
      # 0 is only for now!
      expect(last_invoice.fees.fixed_charge.count).to eq(0)
      # note that charge_recurring_prorated_in_advance should be included, because since it's recurring, it has usage,
      # ewhich we're chargin in_advance
      expect(last_invoice.fees.charge.count).to eq(3)
      expect(last_invoice.fees.charge.map(&:charge_id)).to match_array([charge_metered_not_prorated_in_arrears.id, charge_recurring_prorated_in_arrears.id, charge_recurring_prorated_in_advance.id])

      # check amounts by charges
      metered_not_prorated_fee = last_invoice.fees.charge.find{|fee| fee.charge_id == charge_metered_not_prorated_in_arrears.id}
      recurring_prorated_fee = last_invoice.fees.charge.find{|fee| fee.charge_id == charge_recurring_prorated_in_arrears.id}
      recurring_prorated_advance_fee = last_invoice.fees.charge.find{|fee| fee.charge_id == charge_recurring_prorated_in_advance.id}
      expect(metered_not_prorated_fee.amount_cents).to eq(10_000)
      # this should be 500000 * 10 * 17/31, 
      # prorated_fee_amount = 2_741_935 - this is math correct, but service returns 2_741_940 because of rounding (10 * 17 / 31)...
      prorated_fee_amount = 2_741_940
      expect(recurring_prorated_fee.amount_cents).to eq(prorated_fee_amount)
      expect(recurring_prorated_advance_fee.amount_cents).to eq(50_000_000)

      expect(last_invoice.fees.subscription.count).to eq(1)
      expect(last_invoice.fees.subscription.map{|fee| fee.amount_cents}).to match_array([5_000_000])
      expect(last_invoice.total_amount_cents).to eq(5_000_000 + 50_000_000 + 10_000 + prorated_fee_amount)

      # travel to several dates in the next month and send usages
      [DateTime.new(2024, 4, 10), DateTime.new(2024, 4, 30)].each do |date|
        travel_to(date) do
          [billable_metric_recurring, billable_metric_metered].each do |billable_metric|
            create_event(
              {
                transaction_id: SecureRandom.uuid,
                external_subscription_id: subscription.external_id,
                code: billable_metric.code,
                properties: {
                  billable_metric.field_name => 20
                }
              }
            )
          end
          perform_all_enqueued_jobs
        end
      end

      # we should create invoices for received pay_in_advance charges:
      expect(subscription.reload.invoices.count).to eq(9)
      last_invoices = subscription.invoices.order(:created_at).last(4)
      expect(last_invoices.map{|inv| inv.fees.charge.count}.uniq).to eq([1])
      expect(last_invoices.map{|inv| inv.fees.charge.map(&:charge_id)}.uniq).to match_array([[charge_metered_not_prorated_in_advance.id], [charge_recurring_prorated_in_advance.id]])
      expect(last_invoices.map{|inv| inv.total_amount_cents}.sort).to match_array([200000, 200000, 100000000, 100000000])

      billing_time = DateTime.new(2024, 5, 1)
      travel_to(billing_time) do
        # EventsRecord.connection.commit_db_transaction
        perform_billing
      end
      expect(subscription.reload.invoices.count).to eq(10)
      last_invoice = subscription.invoices.order(:created_at).last
      # 0 is only for now!
      expect(last_invoice.fees.fixed_charge.count).to eq(0)
      # note that charge_recurring_prorated_in_advance should be included, because since it's recurring, it has usage,
      # ewhich we're chargin in_advance
      expect(last_invoice.fees.charge.count).to eq(3)
      expect(last_invoice.fees.charge.map(&:charge_id)).to match_array([charge_metered_not_prorated_in_arrears.id, charge_recurring_prorated_in_arrears.id, charge_recurring_prorated_in_advance.id])

      # check amounts by charges
      metered_not_prorated_fee = last_invoice.fees.charge.find{|fee| fee.charge_id == charge_metered_not_prorated_in_arrears.id}
      recurring_prorated_fee = last_invoice.fees.charge.find{|fee| fee.charge_id == charge_recurring_prorated_in_arrears.id}
      recurring_prorated_advance_fee = last_invoice.fees.charge.find{|fee| fee.charge_id == charge_recurring_prorated_in_advance.id}
      expect(metered_not_prorated_fee.amount_cents).to eq(40_000)
      # this should be current usage: 500000 * 20 * 21/30 + 500000 * 20 * 1/30 + persisted usage:  500000 * 10
      prorated_fee_amount = 7_333_335 + 5000000 # 12_333_333
      expect(recurring_prorated_fee.amount_cents).to eq(prorated_fee_amount)
      # 200_000_000 new usage + 50_000_000 accumulatedfrom previous month
      expect(recurring_prorated_advance_fee.amount_cents).to eq(250_000_000)


      expect(last_invoice.fees.subscription.count).to eq(1)
      expect(last_invoice.fees.subscription.map{|fee| fee.amount_cents}).to match_array([5_000_000])
      expect(last_invoice.total_amount_cents).to eq(5_000_000 + 250_000_000 + 40_000 + prorated_fee_amount)

      # month without any events
      billing_time = DateTime.new(2024, 6, 1)
      travel_to(billing_time) do
        perform_billing
      end
      expect(subscription.reload.invoices.count).to eq(11)
      last_invoice = subscription.invoices.order(:created_at).last
      # 0 is only for now!
      expect(last_invoice.fees.fixed_charge.count).to eq(0)
      # note that charge_recurring_prorated_in_advance should be included, because since it's recurring, it has usage,
      # ewhich we're chargin in_advance
      expect(last_invoice.fees.charge.count).to eq(2)
      expect(last_invoice.fees.charge.map(&:charge_id)).to match_array([charge_recurring_prorated_in_arrears.id, charge_recurring_prorated_in_advance.id])

      # check amounts by charges
      metered_not_prorated_fee = last_invoice.fees.charge.find{|fee| fee.charge_id == charge_metered_not_prorated_in_arrears.id}
      recurring_prorated_fee = last_invoice.fees.charge.find{|fee| fee.charge_id == charge_recurring_prorated_in_arrears.id}
      recurring_prorated_advance_fee = last_invoice.fees.charge.find{|fee| fee.charge_id == charge_recurring_prorated_in_advance.id}
      expect(metered_not_prorated_fee).to eq(nil)
      # 50000 * (10 + 20 + 20) = 2500000
      expect(recurring_prorated_fee.amount_cents).to eq(25_000_000)
      # 200_000_000 new usage + 50_000_000 accumulatedfrom previous month
      expect(recurring_prorated_advance_fee.amount_cents).to eq(250_000_000)


      expect(last_invoice.fees.subscription.count).to eq(1)
      expect(last_invoice.fees.subscription.map{|fee| fee.amount_cents}).to match_array([5_000_000])
      expect(last_invoice.total_amount_cents).to eq(5_000_000 + 250_000_000 + 25_000_000)
    end
  end

  context "without fixed_charges" do
  end
end