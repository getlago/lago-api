# frozen_string_literal: true

require "rails_helper"

describe "Subscription Upgrade Scenario", transaction: false do
  let(:organization) { create(:organization, webhook_url: false, email_settings: []) }

  let(:customer) { create(:customer, organization:) }

  let(:monthly_plan) do
    create(
      :plan,
      organization:,
      interval: "monthly",
      amount_cents: 1000,
      pay_in_advance: true
    )
  end

  let(:yearly_plan) do
    create(
      :plan,
      organization:,
      interval: "yearly",
      amount_cents: 12_000,
      pay_in_advance: true
    )
  end

  let(:subscription_at) { DateTime.new(2023, 6, 29, 12, 12) }

  it "upgrades and bill subscriptions on a regular basis" do
    subscription = nil

    # NOTE: Jun 29th: create the subscription
    travel_to(subscription_at) do
      create_subscription(
        {
          external_customer_id: customer.external_id,
          external_id: customer.external_id,
          plan_code: monthly_plan.code,
          billing_time: "anniversary",
          subscription_at: subscription_at.iso8601
        }
      )

      subscription = customer.subscriptions.first
      expect(subscription).to be_active
      expect(subscription.invoices.count).to eq(1)

      invoice = subscription.invoices.last
      expect(invoice.fees_amount_cents).to eq(monthly_plan.amount_cents)
      expect(invoice.invoice_subscriptions.first.from_datetime.iso8601).to eq("2023-06-29T00:00:00Z")
      expect(invoice.invoice_subscriptions.first.to_datetime.iso8601).to eq("2023-07-28T23:59:59Z")
    end

    # NOTE: July 29th: Bill subscription
    travel_to(DateTime.new(2023, 7, 29, 12, 12)) do
      expect { perform_billing }.to change { subscription.reload.invoices.count }

      expect(subscription.invoices.count).to eq(2)

      invoice = subscription.invoices.order(created_at: :asc).last
      expect(invoice.fees_amount_cents).to eq(monthly_plan.amount_cents)
      expect(invoice.invoice_subscriptions.first.from_datetime.iso8601).to eq("2023-07-29T00:00:00Z")
      expect(invoice.invoice_subscriptions.first.to_datetime.iso8601).to eq("2023-08-28T23:59:59Z")
      expect(invoice.invoice_subscriptions.first.charges_from_datetime.iso8601).to eq("2023-06-29T12:12:00Z")
      expect(invoice.invoice_subscriptions.first.charges_to_datetime.iso8601).to eq("2023-07-28T23:59:59Z")
    end

    # NOTE: August 29th: Bill subscription
    travel_to(DateTime.new(2023, 8, 29, 12, 12)) do
      expect { perform_billing }.to change { subscription.reload.invoices.count }

      expect(subscription.invoices.count).to eq(3)

      invoice = subscription.invoices.order(created_at: :asc).last
      expect(invoice.fees_amount_cents).to eq(monthly_plan.amount_cents)
      expect(invoice.invoice_subscriptions.first.from_datetime.iso8601).to eq("2023-08-29T00:00:00Z")
      expect(invoice.invoice_subscriptions.first.to_datetime.iso8601).to eq("2023-09-28T23:59:59Z")
      expect(invoice.invoice_subscriptions.first.charges_from_datetime.iso8601).to eq("2023-07-29T00:00:00Z")
      expect(invoice.invoice_subscriptions.first.charges_to_datetime.iso8601).to eq("2023-08-28T23:59:59Z")
    end

    # NOTE: On september 28th: Upgrade to the yearly plan
    travel_to(DateTime.new(2023, 9, 28, 5, 0)) do
      create_subscription(
        {
          external_customer_id: customer.external_id,
          external_id: customer.external_id,
          plan_code: yearly_plan.code,
          billing_time: "anniversary"
        }
      )

      expect(subscription.reload).to be_terminated
      expect(subscription.invoices.count).to eq(4)
      expect(customer.invoices.count).to eq(4)

      # expect(invoice.invoice_subscriptions.first.from_datetime.iso8601).to eq('2023-08-29T00:00:00Z')
      # expect(invoice.invoice_subscriptions.first.to_datetime.iso8601).to eq('2023-09-28T23:59:59Z')
      expect(subscription.invoice_subscriptions.order(created_at: :desc).first.charges_from_datetime.iso8601)
        .to eq("2023-08-29T00:00:00Z")
      expect(subscription.invoice_subscriptions.order(created_at: :desc).first.charges_to_datetime.iso8601)
        .to eq("2023-09-28T05:00:00Z")

      new_subscription = customer.subscriptions.order(created_at: :asc).last
      expect(new_subscription.plan.code).to eq(yearly_plan.code)
      expect(new_subscription).to be_active
      expect(new_subscription.invoices.count).to eq(1)

      invoice = new_subscription.invoices.last

      expect(customer.credit_notes.first.credit_amount_cents).to eq(32) # 1000 / 31

      number_of_days = (DateTime.new(2024, 6, 29, 0, 0) - DateTime.new(2023, 9, 28, 0, 0)).to_i
      single_day_price = 12_000.fdiv(366)

      expect(invoice.fees_amount_cents).to eq((number_of_days * single_day_price).round)
    end
  end

  context "when there are fixed charges" do
    let(:plan) { create(:plan, :monthly, pay_in_advance: false, amount_cents: 100, organization:) }
    let(:plan_upgrade) { create(:plan, :monthly, pay_in_advance: false, amount_cents: 10000, organization:) }
    let(:add_ons) { create_list(:add_on, 3, organization:)}
    let(:fixed_charges_plan) {
      [
        create(:fixed_charge, plan:, add_on: add_ons[0], properties: { amount: "1"}, units: 10, pay_in_advance:, prorated:),
        create(:fixed_charge, plan:, add_on: add_ons[1], properties: { amount: "3"}, units: 5, pay_in_advance:, prorated:)
      ]
    }
    let(:fixed_charges_plan_upgrade) {
      [
        create(:fixed_charge, plan: plan_upgrade, add_on: add_ons[1], properties: { amount: "10"}, units: 10, pay_in_advance:, prorated:),
        create(:fixed_charge, plan: plan_upgrade, add_on: add_ons[2], properties: { amount: "20", units: 1 }, pay_in_advance:, prorated:)
      ]
    }

    before do
      fixed_charges_plan
      fixed_charges_plan_upgrade
    end

    context "when fixed charges are in_advance" do
      let(:pay_in_advance) { true }

      context "when fixed charges are prorated" do
        let(:prorated) { true }

        it "calculates all fees" do
          # 2023, 7, 19, 12, 12
          travel_to(subscription_at) do
            create_subscription({
              external_customer_id: customer.external_id,
              external_id: customer.external_id,
              plan_code: plan.code,
              billing_time: "calendar"
            })
          end
          subscription = customer.subscriptions.first
          expect(subscription).to be_active
          expect(subscription.invoices.count).to eq(1)
          invoice = subscription.invoices.order(created_at: :asc).last
          expect(invoice.fees.fixed_charge.count).to eq(2)
          expect(invoice.fees.fixed_charge.map(&:amount_cents)).to match_array([1000 * 13/31, 1500 * 13/31])

          travel_to(DateTime.new(2023, 8, 01, 00, 01)) do
            expect { perform_billing }.to change { subscription.reload.invoices.count }.from(1).to(2)
          end

          invoice = subscription.invoices.order(created_at: :asc).last
          expect(invoice.fees.fixed_charge.count).to eq(2)
          expect(invoice.fees.fixed_charge.map(&:amount_cents)).to match_array([1000, 1500])
          expect(invoice.fees.fixed_charge.sample.properties).to include(
            "fixed_charges_from_datetime" => "2023-08-01T00:00:00.000Z",
            "fixed_charges_to_datetime" => "2023-08-31T23:59:59.999Z"
          )

          travel_to(DateTime.new(2023, 8, 21, 23, 59, 59)) do
            create_subscription(
              {
                external_customer_id: customer.external_id,
                external_id: customer.external_id,
                plan_code: plan_upgrade.code,
                billing_time: "calendar"
              }
            )

            expect(subscription.reload).to be_active
          end
          new_subscription = subscription.reload.next_subscription

          travel_to(DateTime.new(2023, 9, 01, 00, 00, 00)) do
            # we still need to charge subscription fee for the old plan
            byebug
            expect { perform_billing }.to change { subscription.reload.invoices.count }.from(2).to(3)
          end

          # note: this invoice includes both subscriptions: old and new
          invoice = subscription.invoices.order(created_at: :asc).last
          byebug
          expect(invoice.invoice_subscriptions.map(&:subscription)).to match_array([subscription, new_subscription])
          # this invoice contains subscription fee of the old plan
          expect(invoice.fees.subscription.count).to eq(1)
          expect(subscription).to be_terminated

          expect(new_subscription.reload).to be_active
          # and fixed_charges of the new plan
          expect(invoice.fees.fixed_charge.count).to eq(2)
          expect(invoice.fees.fixed_charge.map(&:amount_cents)).to match_array([10000, 2000])
          expect(invoice.fees.fixed_charge.sample.properties).to include(
            "fixed_charges_from_datetime" => "2023-09-01T00:00:00.000Z",
            "fixed_charges_to_datetime" => "2023-09-30T23:59:59.999Z"
          )
        end
      end

      context "when fixed charges are not prorated" do
        let(:prorated) { false }

        it "calculates all fees" do
          # 2023, 7, 19, 12, 12
          travel_to(subscription_at) do
            create_subscription({
              external_customer_id: customer.external_id,
              external_id: customer.external_id,
              plan_code: plan.code,
              billing_time: "calendar"
            })
          end
          subscription = customer.subscriptions.first
          expect(subscription).to be_active
          expect(subscription.invoices.count).to eq(1)
          invoice = subscription.invoices.order(created_at: :asc).last
          expect(invoice.fees.fixed_charge.count).to eq(2)
          expect(invoice.fees.fixed_charge.map(&:amount_cents)).to match_array([1000, 1500])

          travel_to(DateTime.new(2023, 8, 01, 00, 01)) do
            expect { perform_billing }.to change { subscription.reload.invoices.count }.from(1).to(2)
          end

          invoice = subscription.invoices.order(created_at: :asc).last
          expect(invoice.fees.fixed_charge.count).to eq(2)
          expect(invoice.fees.fixed_charge.map(&:amount_cents)).to match_array([1000, 1500])
          expect(invoice.fees.fixed_charge.sample.properties).to include(
            "fixed_charges_from_datetime" => "2023-08-01T00:00:00.000Z",
            "fixed_charges_to_datetime" => "2023-08-31T23:59:59.999Z"
          )

          travel_to(DateTime.new(2023, 8, 21, 23, 59, 59)) do
            create_subscription(
              {
                external_customer_id: customer.external_id,
                external_id: customer.external_id,
                plan_code: plan_upgrade.code,
                billing_time: "calendar"
              }
            )

            expect(subscription.reload).to be_active
          end
          new_subscription = subscription.reload.next_subscription

          travel_to(DateTime.new(2023, 9, 01, 00, 00, 00)) do
            # we still need to charge subscription fee for the old plan
            expect { perform_billing }.to change { subscription.reload.invoices.count }.from(2).to(3)
          end

          # note: this invoice includes both subscriptions: old and new
          invoice = subscription.invoices.order(created_at: :asc).last
          expect(invoice.invoice_subscriptions.map(&:subscription)).to match_array([subscription, new_subscription])
          # this invoice contains subscription fee of the old plan
          expect(invoice.fees.subscription.count).to eq(1)
          expect(subscription).to be_terminated

          expect(new_subscription.reload).to be_active
          # and fixed_charges of the new plan
          expect(invoice.fees.fixed_charge.count).to eq(2)
          expect(invoice.fees.fixed_charge.map(&:amount_cents)).to match_array([10000, 2000])
          expect(invoice.fees.fixed_charge.sample.properties).to include(
            "fixed_charges_from_datetime" => "2023-09-01T00:00:00.000Z",
            "fixed_charges_to_datetime" => "2023-09-30T23:59:59.999Z"
          )
        end
      end
    end

    context "when fixed charges are in_arrears" do
      let(:pay_in_advance) { false }


      context "when fixed charges are prorated" do
        let(:prorated) { true }

        it "calculates all fees" do
          # 2023, 7, 19, 12, 12
          travel_to(subscription_at) do
            create_subscription({
              external_customer_id: customer.external_id,
              external_id: customer.external_id,
              plan_code: plan.code,
              billing_time: "calendar"
            })
          end
          subscription = customer.subscriptions.first
          expect(subscription).to be_active
          expect(subscription.invoices.count).to eq(0)
          travel_to(DateTime.new(2023, 8, 01, 00, 01)) do
            expect { perform_billing }.to change { subscription.reload.invoices.count }.from(0).to(1)
          end

          invoice = subscription.invoices.order(created_at: :asc).last
          expect(invoice.fees.fixed_charge.count).to eq(2)
          expect(invoice.fees.fixed_charge.map(&:amount_cents)).to match_array([1000 * 13/31, 1500 * 13/31])
          expect(invoice.fees.fixed_charge.sample.properties).to include(
            "fixed_charges_from_datetime" => "2023-07-19T12:12:00.000Z",
            "fixed_charges_to_datetime" => "2023-07-31T23:59:59.999Z"
          )

          travel_to(DateTime.new(2023, 8, 21, 23, 59, 59)) do
            create_subscription(
              {
                external_customer_id: customer.external_id,
                external_id: customer.external_id,
                plan_code: plan_upgrade.code,
                billing_time: "calendar"
              }
            )

            expect(subscription.reload).to be_active
          end
          new_subscription = subscription.reload.next_subscription

          travel_to(DateTime.new(2023, 9, 01, 00, 00, 00)) do
            # Now we do charge the old plan
            expect { perform_billing }.to change { subscription.reload.invoices.count }.from(1).to(2)
          end

          # note: this invoice includes only old sub, because there is nothing to charge in the new one
          invoice = subscription.invoices.order(created_at: :asc).last
          expect(invoice.invoice_subscriptions.map(&:subscription)).to match_array([subscription])
          # this invoice contains subscription fee of the old plan
          # and pay in arrears fixed_charges
          expect(invoice.fees.subscription.count).to eq(1)
          expect(invoice.fees.fixed_charge.count).to eq(2)
          expect(invoice.fees.fixed_charge.map(&:amount_cents)).to match_array([1000, 1500])
          # why in this case do we have one more day? :shocked:
          expect(invoice.fees.fixed_charge.sample.properties).to include(
            "fixed_charges_from_datetime" => "2023-08-01T00:00:00.000Z",
            "fixed_charges_to_datetime" => "2023-08-31T23:59:59.999Z"
          )
          expect(subscription).to be_terminated

          expect(new_subscription.reload).to be_active
          expect(new_subscription.invoices.count).to eq(0)

          travel_to(DateTime.new(2023, 10, 01, 00, 00, 00)) do
            # finally charge the new plan (we're in arrears charges); prev invoice is counted for  both subscriptions
            expect { perform_billing }.to change { new_subscription.reload.invoices.count }.from(0).to(1)
          end
          invoice = new_subscription.invoices.order(created_at: :asc).last
          expect(invoice.fees.fixed_charge.count).to eq(2)
          expect(invoice.fees.fixed_charge.map(&:amount_cents)).to match_array([10000, 2000])
          expect(invoice.fees.fixed_charge.sample.properties).to include(
            "fixed_charges_from_datetime" => "2023-09-01T00:00:00.000Z",
            "fixed_charges_to_datetime" => "2023-09-30T23:59:59.999Z"
          )
        end
      end

      context "when fixed charges are not prorated" do
        let(:prorated) { false }

        it "calculates all fees" do
          # 2023, 7, 19, 12, 12
          travel_to(subscription_at) do
            create_subscription({
              external_customer_id: customer.external_id,
              external_id: customer.external_id,
              plan_code: plan.code,
              billing_time: "calendar"
            })
          end
          subscription = customer.subscriptions.first
          expect(subscription).to be_active
          expect(subscription.invoices.count).to eq(0)

          travel_to(DateTime.new(2023, 8, 01, 00, 01)) do
            expect { perform_billing }.to change { subscription.reload.invoices.count }.from(0).to(1)
          end

          invoice = subscription.invoices.order(created_at: :asc).last
          expect(invoice.fees.fixed_charge.count).to eq(2)
          expect(invoice.fees.fixed_charge.map(&:amount_cents)).to match_array([1000, 1500])
          expect(invoice.fees.fixed_charge.sample.properties).to include(
            "fixed_charges_from_datetime" => "2023-07-19T12:12:00.000Z",
            "fixed_charges_to_datetime" => "2023-07-31T23:59:59.999Z"
          )

          travel_to(DateTime.new(2023, 8, 21, 23, 59, 59)) do
            create_subscription(
              {
                external_customer_id: customer.external_id,
                external_id: customer.external_id,
                plan_code: plan_upgrade.code,
                billing_time: "calendar"
              }
            )

            expect(subscription.reload).to be_active
          end
          new_subscription = subscription.reload.next_subscription

          travel_to(DateTime.new(2023, 9, 01, 00, 00, 00)) do
            # Now we do charge the old plan
            expect { perform_billing }.to change { subscription.reload.invoices.count }.from(1).to(2)
          end

          # note: this invoice includes only old sub, because there is nothing to charge in the new one
          invoice = subscription.invoices.order(created_at: :asc).last
          expect(invoice.invoice_subscriptions.map(&:subscription)).to match_array([subscription])
          # this invoice contains subscription fee of the old plan
          expect(invoice.fees.subscription.count).to eq(1)
          expect(invoice.fees.fixed_charge.count).to eq(2)
          expect(invoice.fees.fixed_charge.map(&:amount_cents)).to match_array([1000, 1500])
          expect(invoice.fees.fixed_charge.sample.properties).to include(
            "fixed_charges_from_datetime" => "2023-08-01T00:00:00.000Z",
            "fixed_charges_to_datetime" => "2023-08-31T23:59:59.999Z"
          )
          expect(subscription).to be_terminated

          expect(new_subscription.reload).to be_active
          expect(new_subscription.invoices.count).to eq(0)

          travel_to(DateTime.new(2023, 10, 01, 00, 00, 00)) do
            # finally charge the new plan (we're in arrears charges); prev invoice is counted for  both subscriptions
            expect { perform_billing }.to change { new_subscription.reload.invoices.count }.from(0).to(1)
          end
          invoice = new_subscription.invoices.order(created_at: :asc).last
          expect(invoice.fees.fixed_charge.count).to eq(2)
          expect(invoice.fees.fixed_charge.map(&:amount_cents)).to match_array([10000, 2000])
          expect(invoice.fees.fixed_charge.sample.properties).to include(
            "fixed_charges_from_datetime" => "2023-09-01T00:00:00.000Z",
            "fixed_charges_to_datetime" => "2023-09-30T23:59:59.999Z"
          )
        end
      end
    end
  end
end
