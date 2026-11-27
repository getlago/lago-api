# frozen_string_literal: true

require "rails_helper"

# End-to-end scenario: regenerating a voided advance_charges invoice.
#
# Flow:
#   1. Create a plan with a pay-in-advance, non-invoiceable charge (regroup_paid_fees: invoice)
#   2. Subscribe a customer and ingest events that produce pay-in-advance fees
#   3. Run billing to group those fees into an advance_charges invoice
#   4. Void the invoice
#   5. Regenerate it with adjusted fee params
#
# This exercises three fixes:
#   - the idx_pay_in_advance_duplication_guard_charge unique index now allows
#     duplicate pay_in_advance_event_transaction_id on regenerated fees
#   - create_invoice_subscriptions now runs for any voided invoice that had them,
#     not only subscription-type invoices
#   - AdjustedFees::CreateService only calls RefreshDraftService for draft
#     subscription invoices, avoiding forbidden_failure! on advance_charges
#
describe "Regenerate Voided Advance Charges Invoice Scenarios", :with_pdf_generation_stub, transaction: false do
  include GraphQLHelper

  let(:organization) { create(:organization, webhook_url: nil) }
  let(:customer) { create(:customer, organization:) }
  let(:tax_rate) { 20 }
  let(:billable_metric) { create(:unique_count_billable_metric, organization:, code: "cards", recurring: true) }
  let(:plan) { create(:plan, organization:, pay_in_advance: true, amount_cents: 49) }
  let(:external_subscription_id) { SecureRandom.uuid }

  def send_card_event!(item_id = SecureRandom.uuid)
    create_event({
      code: billable_metric.code,
      transaction_id: "tr_#{SecureRandom.hex(10)}",
      external_customer_id: customer.external_id,
      external_subscription_id:,
      properties: {item_id:}
    })
  end

  def create_advance_charges_invoice
    travel_to(DateTime.new(2024, 6, 5, 10)) do
      create_subscription(
        {
          external_customer_id: customer.external_id,
          external_id: external_subscription_id,
          plan_code: plan.code
        }
      )
      perform_billing
    end

    subscription = customer.subscriptions.sole

    (1..3).each do |i|
      travel_to(DateTime.new(2024, 6, 10 + i, 10)) do
        send_card_event! "card_#{i}"
      end
    end

    subscription.fees.charge.where(invoice_id: nil).update!(
      payment_status: :succeeded,
      succeeded_at: DateTime.new(2024, 6, 20, 0, 10)
    )

    travel_to(DateTime.new(2024, 7, 1, 0, 10)) do
      perform_billing
    end

    invoice = customer.invoices.where(invoice_type: :advance_charges).sole
    expect(invoice).to be_finalized
    expect(invoice.fees.count).to eq(3)
    expect(invoice.invoice_subscriptions).not_to be_empty

    invoice
  end

  def regenerate_with_five_units(voided_invoice)
    Invoices::RegenerateFromVoidedService.call!(
      voided_invoice:,
      fees_params: [
        {id: voided_invoice.fees.first.id, subscription_id: customer.subscriptions.sole.id, units: 5, unit_amount_cents: 20.0}
      ]
    ).invoice
  end

  def create_wallet_with_credits
    create_wallet({
      external_customer_id: customer.external_id,
      rate_amount: "1",
      currency: "EUR",
      granted_credits: "50",
      invoice_requires_successful_payment: false
    }, as: :model)
  end

  before do
    create(:tax, :applied_to_billing_entity, organization:, rate: tax_rate)
    create(
      :standard_charge,
      regroup_paid_fees: "invoice",
      pay_in_advance: true,
      invoiceable: false,
      prorated: true,
      billable_metric:,
      plan:,
      properties: {amount: "30.12", grouped_by: nil}
    )
  end

  context "when regenerating with fee id (primary UI path)" do
    it "regenerates a voided advance_charges invoice with adjusted fees" do
      advance_charges_invoice = create_advance_charges_invoice
      subscription = customer.subscriptions.sole
      original_fee = advance_charges_invoice.fees.first

      void_invoice(advance_charges_invoice)
      expect(advance_charges_invoice).to be_voided

      fees_params = [
        {
          id: original_fee.id,
          subscription_id: subscription.id,
          units: 5,
          unit_amount_cents: 20.0
        }
      ]

      result = Invoices::RegenerateFromVoidedService.call(
        voided_invoice: advance_charges_invoice,
        fees_params:
      )

      expect(result).to be_success

      regenerated_invoice = result.invoice
      expect(regenerated_invoice.invoice_type).to eq("advance_charges")
      expect(regenerated_invoice).to be_finalized
      expect(regenerated_invoice.invoice_subscriptions).not_to be_empty

      regenerated_fee = regenerated_invoice.fees.first
      expect(regenerated_fee.pay_in_advance_event_transaction_id).to eq(original_fee.pay_in_advance_event_transaction_id)
      expect(regenerated_fee.units).to eq(5)
      expect(regenerated_fee.unit_amount_cents).to eq(2000)
      expect(regenerated_fee.amount_cents).to eq(10_000)

      # Original fee on the voided invoice is untouched
      expect(original_fee.reload.pay_in_advance_event_transaction_id).to be_present
    end
  end

  context "when regenerating through the regenerateFromVoided mutation" do
    let(:membership) { create(:membership, organization:) }
    let(:mutation) do
      <<~GQL
        mutation($input: RegenerateInvoiceInput!) {
          regenerateFromVoided(input: $input) { id }
        }
      GQL
    end

    def regenerate_through_mutation(voided_invoice, fees)
      data = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: "invoices:update",
        query: mutation,
        variables: {input: {voidedInvoiceId: voided_invoice.id, fees:}}
      )
      Invoice.find(data.dig("data", "regenerateFromVoided", "id"))
    end

    it "applies the current customer taxes and leaves the invoice to be paid" do
      advance_charges_invoice = create_advance_charges_invoice
      subscription = customer.subscriptions.sole
      original_fee = advance_charges_invoice.fees.first

      void_invoice(advance_charges_invoice)
      expect(advance_charges_invoice).to be_voided

      create(:customer_applied_tax, customer:, tax: create(:tax, organization:, rate: 8.5))

      regenerated_invoice = regenerate_through_mutation(
        advance_charges_invoice,
        [{id: original_fee.id, subscriptionId: subscription.id, units: 5, unitAmountCents: 20.0}]
      )
      perform_all_enqueued_jobs

      expect(regenerated_invoice.reload).to have_attributes(
        invoice_type: "advance_charges",
        status: "finalized",
        fees_amount_cents: 10_000, # 5 units * 2000 cents
        taxes_amount_cents: 850, # 10000 * 8.5% customer tax, which replaces the 20% billing entity tax
        total_amount_cents: 10_850, # 10000 + 850
        payment_status: "pending"
      )
      expect(Payment.where(payable: regenerated_invoice)).to be_empty
    end

    it "settles the invoice with the credit note of the voided invoice", :premium do
      advance_charges_invoice = create_advance_charges_invoice
      subscription = customer.subscriptions.sole
      original_fee = advance_charges_invoice.fees.first
      original_total = advance_charges_invoice.total_amount_cents

      void_invoice(advance_charges_invoice, generate_credit_note: true, credit_amount: original_total)
      expect(advance_charges_invoice).to be_voided
      credit_note = advance_charges_invoice.credit_notes.sole
      expect(credit_note.balance_amount_cents).to eq(original_total)

      regenerated_invoice = regenerate_through_mutation(
        advance_charges_invoice,
        [{id: original_fee.id, subscriptionId: subscription.id, units: 1, unitAmountCents: 10.0}]
      )
      perform_all_enqueued_jobs

      expect(regenerated_invoice.reload).to have_attributes(
        invoice_type: "advance_charges",
        status: "finalized",
        fees_amount_cents: 1_000, # 1 unit * 1000 cents
        taxes_amount_cents: 200, # 1000 * 20% billing entity tax
        credit_notes_amount_cents: 1_200, # 1000 + 200
        total_amount_cents: 0,
        payment_status: "succeeded"
      )
      expect(credit_note.reload.balance_amount_cents).to eq(original_total - 1_200)
      expect(Payment.where(payable: regenerated_invoice)).to be_empty
    end
  end

  context "when the customer has a tax provider", :premium do
    it "computes the taxes without committing them at the provider and charges the payment provider" do
      advance_charges_invoice = create_advance_charges_invoice
      subscription = customer.subscriptions.sole
      original_fee = advance_charges_invoice.fees.first

      void_invoice(advance_charges_invoice)
      expect(advance_charges_invoice).to be_voided

      # The tax provider and the payment provider are connected after the original invoice is voided.
      anrok_customer = create(:anrok_customer, integration: create(:anrok_integration, organization:), customer:)
      customer.update!(payment_provider: "stripe")

      result = Invoices::RegenerateFromVoidedService.call(
        voided_invoice: advance_charges_invoice,
        fees_params: [{id: original_fee.id, subscription_id: subscription.id, units: 5, unit_amount_cents: 20.0}]
      )

      expect(result).to be_success
      regenerated_invoice = result.invoice
      expect(regenerated_invoice).to have_attributes(status: "pending", tax_status: "pending")
      expect(Invoices::ProviderTaxes::PullTaxesAndApplyJob).to have_been_enqueued.with(invoice: regenerated_invoice)

      # No action other than this estimate is answered.
      regenerated_fee = regenerated_invoice.fees.sole
      anrok_estimate = stub_anrok_taxes(
        "anrok-create-ephemeral-transaction",
        integration_customer: anrok_customer,
        invoice: regenerated_invoice,
        fees: [{"item_key" => regenerated_fee.item_key, "item_id" => regenerated_fee.id, "item_code" => nil, "amount_cents" => 10_000}]
      )

      expect do
        perform_all_enqueued_jobs(only: [Invoices::ProviderTaxes::PullTaxesAndApplyJob])
      end.to have_enqueued_job(Invoices::Payments::CreateJob)
        .with(invoice: regenerated_invoice, payment_provider: :stripe, payment_method_params: {})

      expect(anrok_estimate).to have_been_requested.once
      expect(a_request(:post, AnrokHelper::NANGO_ACTION_ENDPOINT)).to have_been_made.once # nothing committed at Anrok
      expect(regenerated_invoice.reload).to have_attributes(
        invoice_type: "advance_charges",
        status: "finalized",
        tax_status: "succeeded",
        fees_amount_cents: 10_000, # 5 units * 2000 cents
        taxes_amount_cents: 990, # Anrok tax_amount_cents from success_response.json
        total_amount_cents: 10_990, # 10000 + 990
        payment_status: "pending"
      )
      expect(Payment.where(payable: regenerated_invoice)).to be_empty
    end
  end

  context "when the customer pays with Stripe" do
    include_context "with Stripe configured for customer"

    let(:payment_intents_endpoint) { "https://api.stripe.com/v1/payment_intents" }

    before do
      # Each payment intent gets its own id, as the subscription invoice is also charged.
      stub_request(:post, payment_intents_endpoint).and_return(
        status: 402,
        body: lambda { |_request|
          get_stripe_fixtures("payment_intent_card_declined_response.json") do |h|
            h[:error][:payment_intent][:id] = "pi_#{SecureRandom.hex}"
          end
        }
      )
    end

    it "applies neither the coupon nor the wallet and charges the full total" do
      advance_charges_invoice = create_advance_charges_invoice

      # The wallet and the coupon are added after the original invoice was issued, so only the regenerated one could use them.
      wallet = create_wallet_with_credits
      expect(wallet.reload.balance_cents).to eq(5_000)
      create_coupon({
        name: "Recurring",
        code: "recurring",
        coupon_type: "fixed_amount",
        amount_cents: 1_000,
        amount_currency: "EUR",
        frequency: "recurring",
        frequency_duration: 3,
        expiration: "no_expiration"
      })
      apply_coupon({external_customer_id: customer.external_id, coupon_code: "recurring"})
      applied_coupon = customer.applied_coupons.sole
      expect(applied_coupon).to have_attributes(status: "active", frequency_duration_remaining: 3)

      void_invoice(advance_charges_invoice)
      regenerated_invoice = regenerate_with_five_units(advance_charges_invoice)
      expect(regenerated_invoice).to have_attributes(status: "finalized", payment_status: "pending")

      perform_all_enqueued_jobs

      expect(regenerated_invoice.reload).to have_attributes(
        invoice_type: "advance_charges",
        fees_amount_cents: 10_000, # 5 units * 2000 cents
        coupons_amount_cents: 0,
        taxes_amount_cents: 2_000, # 10000 * 20% billing entity tax
        prepaid_credit_amount_cents: 0,
        total_amount_cents: 12_000, # 10000 + 2000
        payment_status: "failed" # the Stripe stub declines the card
      )
      expect(a_request(:post, payment_intents_endpoint).with(body: hash_including("amount" => "12000")))
        .to have_been_made.once
      expect(wallet.reload.balance_cents).to eq(5_000)
      expect(WalletTransaction.where(invoice: regenerated_invoice)).to be_empty
      expect(applied_coupon.reload).to have_attributes(status: "active", frequency_duration_remaining: 3)
      expect(Credit.where(invoice: regenerated_invoice)).to be_empty
    end

    it "applies a partial credit note of the voided invoice and charges the rest", :premium do
      advance_charges_invoice = create_advance_charges_invoice

      void_invoice(advance_charges_invoice, generate_credit_note: true, credit_amount: 1_000)
      # The rest of the voided invoice goes to a second credit note, voided at once.
      credit_note = advance_charges_invoice.credit_notes.where.not(credit_status: :voided).sole
      expect(credit_note.balance_amount_cents).to eq(1_000)

      regenerated_invoice = regenerate_with_five_units(advance_charges_invoice)
      expect(regenerated_invoice).to have_attributes(
        status: "finalized",
        fees_amount_cents: 10_000, # 5 units * 2000 cents
        taxes_amount_cents: 2_000, # 10000 * 20% billing entity tax
        credit_notes_amount_cents: 1_000,
        total_amount_cents: 11_000, # 10000 + 2000 - 1000 credit note
        payment_status: "pending"
      )
      expect(credit_note.reload.balance_amount_cents).to eq(0)

      perform_all_enqueued_jobs

      expect(a_request(:post, payment_intents_endpoint).with(body: hash_including("amount" => "11000")))
        .to have_been_made.once
    end
  end

  context "when the VIES check of the customer is pending" do
    let(:vat_number) { "IT12345678901" }

    it "finalizes the invoice with taxes and without the wallet once the check completes" do
      advance_charges_invoice = create_advance_charges_invoice
      void_invoice(advance_charges_invoice)
      wallet = create_wallet_with_credits

      update_billing_entity(customer.billing_entity, {country: "FR", eu_tax_management: true})

      # VIES is unavailable when the customer gives its VAT number: the check stays pending.
      mock_vies_check_unavailable(vat_number)
      create_or_update_customer(
        {external_id: customer.external_id, country: "IT", zipcode: "00146", tax_identification_number: vat_number},
        perform_jobs: false
      )
      perform_enqueued_jobs(only: Customers::ViesCheckJob)
      perform_all_enqueued_jobs(except: [Customers::ViesCheckJob])
      # Drop the scheduled retry, so the example decides when VIES answers.
      queue_adapter.enqueued_jobs.reject! { |job| job[:job] == Customers::ViesCheckJob }
      expect(customer.reload.vies_check_in_progress?).to be(true)

      regenerated_invoice = regenerate_with_five_units(advance_charges_invoice)
      expect(regenerated_invoice.reload).to have_attributes(status: "pending", tax_status: "pending")

      mock_vies_check(vat_number)
      Customers::ViesCheckJob.perform_now(customer)
      perform_all_enqueued_jobs
      expect(customer.reload.vies_check_in_progress?).to be(false)

      expect(regenerated_invoice.reload).to have_attributes(
        invoice_type: "advance_charges",
        status: "finalized",
        tax_status: "succeeded",
        fees_amount_cents: 10_000, # 5 units * 2000 cents
        taxes_amount_cents: 0, # 10000 * 0% EU reverse charge, the customer tax once VIES validates the VAT number
        prepaid_credit_amount_cents: 0,
        total_amount_cents: 10_000, # 10000 + 0
        payment_status: "pending"
      )
      expect(regenerated_invoice.applied_taxes.sole.tax_code).to eq("lago_eu_reverse_charge")
      expect(wallet.reload.balance_cents).to eq(5_000)
      expect(WalletTransaction.where(invoice: regenerated_invoice)).to be_empty
    end
  end

  context "when a manual payment is recorded through the API" do
    def regenerated_pending_invoice
      advance_charges_invoice = create_advance_charges_invoice
      void_invoice(advance_charges_invoice)

      regenerate_with_five_units(advance_charges_invoice).tap do |invoice|
        perform_all_enqueued_jobs
        expect(invoice.reload).to have_attributes(total_amount_cents: 12_000, payment_status: "pending") # 10000 + 20% tax
      end
    end

    it "marks the regenerated invoice as paid", :premium do
      regenerated_invoice = regenerated_pending_invoice

      create_payment(customer, regenerated_invoice, 12_000)

      expect(Payment.where(payable: regenerated_invoice).sole).to have_attributes(
        amount_cents: 12_000,
        payment_type: "manual",
        payable_payment_status: "succeeded"
      )
      expect(regenerated_invoice.reload).to have_attributes(total_paid_amount_cents: 12_000, payment_status: "succeeded")
    end

    it "refuses the payment without a premium license" do
      regenerated_invoice = regenerated_pending_invoice

      create_payment(customer, regenerated_invoice, 12_000, raise_on_error: false)

      expect(response).to have_http_status(:forbidden)
      expect(json[:code]).to eq("feature_unavailable")
      expect(Payment.where(payable: regenerated_invoice)).to be_empty
      expect(regenerated_invoice.reload).to have_attributes(total_paid_amount_cents: 0, payment_status: "pending")
    end
  end

  context "when multiple void/regenerate cycles occur" do
    it "preserves pay_in_advance_event_transaction_id across the chain" do
      advance_charges_invoice = create_advance_charges_invoice
      subscription = customer.subscriptions.sole
      original_fee = advance_charges_invoice.fees.first
      original_transaction_id = original_fee.pay_in_advance_event_transaction_id

      # First cycle: void → regenerate
      void_invoice(advance_charges_invoice)

      first_result = Invoices::RegenerateFromVoidedService.call(
        voided_invoice: advance_charges_invoice,
        fees_params: [{id: original_fee.id, subscription_id: subscription.id, units: 5, unit_amount_cents: 20.0}]
      )
      expect(first_result).to be_success

      first_regenerated_invoice = first_result.invoice
      first_regenerated_fee = first_regenerated_invoice.fees.first
      expect(first_regenerated_fee.pay_in_advance_event_transaction_id).to eq(original_transaction_id)

      # Second cycle: void the regenerated invoice → regenerate again
      void_invoice(first_regenerated_invoice)
      expect(first_regenerated_invoice).to be_voided

      second_result = Invoices::RegenerateFromVoidedService.call(
        voided_invoice: first_regenerated_invoice,
        fees_params: [{id: first_regenerated_fee.id, subscription_id: subscription.id, units: 8, unit_amount_cents: 15.0}]
      )
      expect(second_result).to be_success

      second_regenerated_invoice = second_result.invoice
      second_regenerated_fee = second_regenerated_invoice.fees.first

      # pay_in_advance_event_transaction_id is preserved across all regenerations
      expect(second_regenerated_fee.pay_in_advance_event_transaction_id).to eq(original_transaction_id)
      expect(second_regenerated_fee.units).to eq(8)
      expect(second_regenerated_fee.unit_amount_cents).to eq(1500)
    end
  end

  context "when regenerating without fee id (charge-based path)" do
    it "creates fees via invoice_subscriptions and adjusts them" do
      advance_charges_invoice = create_advance_charges_invoice
      subscription = customer.subscriptions.sole
      charge = subscription.plan.charges.first

      void_invoice(advance_charges_invoice)
      expect(advance_charges_invoice).to be_voided

      fees_params = [
        {
          subscription_id: subscription.id,
          charge_id: charge.id,
          units: 5,
          unit_amount_cents: 20.0
        }
      ]

      result = Invoices::RegenerateFromVoidedService.call(
        voided_invoice: advance_charges_invoice,
        fees_params:
      )

      expect(result).to be_success

      regenerated_invoice = result.invoice
      expect(regenerated_invoice.invoice_type).to eq("advance_charges")
      expect(regenerated_invoice).to be_finalized
      expect(regenerated_invoice.invoice_subscriptions).not_to be_empty
      expect(regenerated_invoice.fees.count).to be >= 1
    end
  end
end
