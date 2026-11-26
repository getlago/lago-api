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
    let(:anrok_client) { instance_double(LagoHttpClient::Client) }
    let(:nango_action_endpoint) { "https://api.nango.dev/action/trigger" }
    let(:success_body_template) do
      JSON.parse(File.read(Rails.root.join("spec/fixtures/integration_aggregator/taxes/invoices/success_response.json")))
    end

    before do
      allow(LagoHttpClient::Client).to receive(:new).and_call_original
      allow(LagoHttpClient::Client).to receive(:new).with(nango_action_endpoint, anything).and_return(anrok_client)
      allow(anrok_client).to receive(:post_with_response) do
        # Anrok answers for the fees it receives, so its fee entry carries the regenerated fee id.
        body = success_body_template.deep_dup
        body["succeededInvoices"].first["fees"].first["item_id"] = customer.invoices.pending.sole.fees.sole.id
        instance_double(Net::HTTPOK, body: body.to_json)
      end
    end

    it "computes the taxes without committing them at the provider and charges the payment provider" do
      advance_charges_invoice = create_advance_charges_invoice
      subscription = customer.subscriptions.sole
      original_fee = advance_charges_invoice.fees.first

      void_invoice(advance_charges_invoice)
      expect(advance_charges_invoice).to be_voided

      # The tax provider and the payment provider are connected after the original invoice is voided.
      create(:anrok_customer, integration: create(:anrok_integration, organization:), customer:)
      customer.update!(payment_provider: "stripe")

      result = Invoices::RegenerateFromVoidedService.call(
        voided_invoice: advance_charges_invoice,
        fees_params: [{id: original_fee.id, subscription_id: subscription.id, units: 5, unit_amount_cents: 20.0}]
      )

      expect(result).to be_success
      regenerated_invoice = result.invoice
      expect(regenerated_invoice).to have_attributes(status: "pending", tax_status: "pending")
      expect(Invoices::ProviderTaxes::PullTaxesAndApplyJob).to have_been_enqueued.with(invoice: regenerated_invoice)

      expect do
        perform_all_enqueued_jobs(only: [Invoices::ProviderTaxes::PullTaxesAndApplyJob])
      end.to have_enqueued_job(Invoices::Payments::CreateJob)
        .with(invoice: regenerated_invoice, payment_provider: :stripe, payment_method_params: {})

      expect(anrok_client).to have_received(:post_with_response)
        .with(hash_including(action_name: "anrok-create-ephemeral-transaction"), anything)
      expect(anrok_client).not_to have_received(:post_with_response)
        .with(hash_including(action_name: "anrok-create-or-update-transaction"), anything)
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
