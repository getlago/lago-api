# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invoice, type: :model do
  subject(:invoice) { create(:invoice, organization:) }

  let(:organization) { create(:organization) }

  it_behaves_like "paper_trail traceable"

  it { is_expected.to have_many(:integration_resources) }
  it { is_expected.to have_many(:error_details) }

  it { is_expected.to have_many(:progressive_billing_credits) }

  it { is_expected.to have_many(:applied_payment_requests).class_name("PaymentRequest::AppliedInvoice") }
  it { is_expected.to have_many(:payment_requests).through(:applied_payment_requests) }
  it { is_expected.to have_many(:payments) }
  it { is_expected.to have_many(:payment_receipts).through(:payments) }

  it { is_expected.to have_many(:applied_usage_thresholds) }
  it { is_expected.to have_many(:usage_thresholds).through(:applied_usage_thresholds) }

  describe "Clickhouse associations", clickhouse: true do
    it { is_expected.to have_many(:activity_logs).class_name("Clickhouse::ActivityLog") }
  end

  it { is_expected.to belong_to(:billing_entity).optional }

  it "has fixed status mapping" do
    expect(described_class::VISIBLE_STATUS).to match(draft: 0, finalized: 1, voided: 2, failed: 4, pending: 7)
    expect(described_class::INVISIBLE_STATUS).to match(generating: 3, open: 5, closed: 6)
    expect(described_class::STATUS).to match(draft: 0, finalized: 1, voided: 2, generating: 3, failed: 4, open: 5, closed: 6, pending: 7)
  end

  describe "validation" do
    describe "of payment dispute lost absence" do
      context "when invoice is not voided" do
        let(:invoice) { create(:invoice) }

        specify do
          expect(invoice).not_to validate_absence_of(:payment_dispute_lost_at)
        end
      end

      context "when invoice is voided" do
        let(:invoice) { create(:invoice, status: :voided) }

        specify do
          expect(invoice).to validate_absence_of(:payment_dispute_lost_at)
        end
      end
    end
  end

  describe "finalized_at" do
    let(:invoice) { create(:invoice, :draft) }

    it "is set when the invoice is finalized" do
      freeze_time do
        invoice.finalized!

        expect(invoice.finalized_at).to eq(Time.current)
      end
    end
  end

  describe "sequential_id" do
    let(:customer) { create(:customer, organization:) }
    let(:billing_entity) { customer.billing_entity }

    let(:invoice) do
      build(:invoice, customer:, organization:, billing_entity:, billing_entity_sequential_id: nil, organization_sequential_id: 0, status: :generating)
    end

    it "assigns a sequential id, billing entity sequential id and organization sequential id to a new invoice" do
      invoice.save!
      invoice.finalized!

      expect(invoice).to be_valid
      expect(invoice.sequential_id).to eq(1)
      expect(invoice.billing_entity_sequential_id).to be_nil
      expect(invoice.organization_sequential_id).to be_zero
    end

    context "when sequential_id, billing_entity_sequential_id and organization_sequential_id are present" do
      before do
        invoice.sequential_id = 3
        invoice.billing_entity_sequential_id = 2
        invoice.organization_sequential_id = 5
      end

      it "does not replace the sequential_id, billing_entity_sequential_id and organization_sequential_id" do
        invoice.save!
        invoice.finalized!

        expect(invoice).to be_valid
        expect(invoice.sequential_id).to eq(3)
        expect(invoice.billing_entity_sequential_id).to eq(2)
        expect(invoice.organization_sequential_id).to eq(5)
      end
    end

    context "when customer already has invoices" do
      before do
        create(:invoice, customer:, organization:, billing_entity:, sequential_id: 1, billing_entity_sequential_id: 1, organization_sequential_id: 0)
        create(:invoice, customer:, organization:, billing_entity:, sequential_id: 2, billing_entity_sequential_id: 2, organization_sequential_id: 0)
      end

      it "takes the next available id" do
        invoice.save!
        invoice.finalized!

        expect(invoice).to be_valid
        expect(invoice.sequential_id).to eq(3)
        expect(invoice.billing_entity_sequential_id).to be_nil
        expect(invoice.organization_sequential_id).to be_zero
      end
    end

    context "with invoices in other billing entities" do
      let(:billing_entity_2) { create(:billing_entity, organization:) }

      before do
        create(:invoice, organization:, billing_entity: billing_entity_2, sequential_id: 1, billing_entity_sequential_id: 1, organization_sequential_id: 0)
        create(:invoice, organization:, billing_entity: billing_entity_2, sequential_id: 2, billing_entity_sequential_id: 2, organization_sequential_id: 0)
      end

      it "scopes the sequences to the billing entity" do
        invoice.save!
        invoice.finalized!

        expect(invoice).to be_valid
        expect(invoice.sequential_id).to eq(1)
        expect(invoice.billing_entity_sequential_id).to be_nil
        expect(invoice.organization_sequential_id).to be_zero
      end
    end

    context "with invoices on other organization" do
      before do
        create(:invoice, sequential_id: 1, organization_sequential_id: 0)
      end

      it "scopes the sequence to the organization" do
        invoice.save!
        invoice.finalized!

        expect(invoice).to be_valid
        expect(invoice.sequential_id).to eq(1)
        expect(invoice.organization_sequential_id).to be_zero
      end
    end

    context "with billing_entity numbering and invoices in another month" do
      let(:organization) { create(:organization, document_numbering: "per_organization") }
      let(:created_at) { Time.now.utc - 1.month }

      before do
        organization.default_billing_entity.update!(document_numbering: "per_billing_entity")
        create(:invoice, customer:, organization:, sequential_id: 1, billing_entity_sequential_id: 1, organization_sequential_id: 1, created_at:)
        create(:invoice, customer:, organization:, sequential_id: 2, billing_entity_sequential_id: 2, organization_sequential_id: 2, created_at:)
      end

      it "scopes the billing_entity_sequential_id to the billing_entity and month" do
        invoice.save!
        invoice.finalized!

        expect(invoice).to be_valid
        expect(invoice.sequential_id).to eq(3)
        expect(invoice.billing_entity_sequential_id).to eq(3)
        # expect(invoice.organization_sequential_id).to eq(3)
      end
    end
  end

  describe "ready_to_be_finalized" do
    let(:invoice) { create(:invoice, status: :draft, issuing_date: Time.current - 1.day) }

    before { invoice }

    it "returns all invoices that are ready for finalization" do
      expect(described_class.ready_to_be_finalized.pluck(:id)).to include(invoice.id)
    end

    context "when issuing date has not been reached" do
      let(:invoice) { create(:invoice, status: :draft, issuing_date: Time.current + 1.day) }

      it "returns all invoices that are ready for finalization" do
        expect(described_class.ready_to_be_finalized.pluck(:id)).not_to include(invoice.id)
      end
    end
  end

  describe "ready_to_be_refreshed" do
    let(:invoices) do
      [
        create(:invoice, status: :draft, ready_to_be_refreshed: true),
        create(:invoice, status: :draft, ready_to_be_refreshed: false),
        create(:invoice, status: :finalized, ready_to_be_refreshed: true)
      ]
    end

    before { invoices }

    it "returns only the invoices that are ready for refresh" do
      expect(described_class.ready_to_be_finalized.pluck(:id)).to include(invoices[0].id)
    end
  end

  describe "when status is visible" do
    it do
      described_class::VISIBLE_STATUS.keys.each do |status|
        i = create(:invoice, status:)
        expect(i).to be_visible
        expect(i).not_to be_invisible
      end
    end
  end

  describe "when status is invisible" do
    it do
      described_class::INVISIBLE_STATUS.keys.each do |status|
        i = create(:invoice, status:)
        expect(i).to be_invisible
        expect(i).not_to be_visible
      end
    end
  end

  describe "#should_sync_invoice?" do
    subject(:method_call) { invoice.should_sync_invoice? }

    let(:invoice) { create(:invoice, customer:, organization:, status:) }

    context "when invoice is not finalized" do
      let(:status) { %i[draft generating voided].sample }

      context "without integration customer" do
        let(:customer) { create(:customer, organization:) }

        it "returns false" do
          expect(method_call).to eq(false)
        end
      end

      context "with integration customer" do
        let(:integration_customer) { create(:netsuite_customer, integration:, customer:) }
        let(:integration) { create(:netsuite_integration, organization:, sync_invoices:) }
        let(:customer) { create(:customer, organization:) }

        before { integration_customer }

        context "when sync invoices is true" do
          let(:sync_invoices) { true }

          it "returns false" do
            expect(method_call).to eq(false)
          end
        end

        context "when sync invoices is false" do
          let(:sync_invoices) { false }

          it "returns false" do
            expect(method_call).to eq(false)
          end
        end
      end
    end

    context "when invoice is finalized" do
      let(:status) { :finalized }

      context "without integration customer" do
        let(:customer) { create(:customer, organization:) }

        it "returns false" do
          expect(method_call).to eq(false)
        end
      end

      context "with integration customer" do
        let(:integration_customer) { create(:netsuite_customer, integration:, customer:) }
        let(:integration) { create(:netsuite_integration, organization:, sync_invoices:) }
        let(:customer) { create(:customer, organization:) }

        before { integration_customer }

        context "when sync invoices is true" do
          let(:sync_invoices) { true }

          it "returns true" do
            expect(method_call).to eq(true)
          end
        end

        context "when sync invoices is false" do
          let(:sync_invoices) { false }

          it "returns false" do
            expect(method_call).to eq(false)
          end
        end

        context "when the invoice is self_billed" do
          let(:invoice) { create(:invoice, customer:, organization:, status:, self_billed: true) }
          let(:sync_invoices) { true }

          it "returns false" do
            expect(method_call).to eq(false)
          end
        end
      end
    end
  end

  describe "#should_sync_salesforce_invoice?" do
    subject(:method_call) { invoice.should_sync_salesforce_invoice? }

    let(:invoice) { create(:invoice, customer:, organization:, status: :finalized) }

    context "with integration salesforce customer" do
      let(:integration_customer) { create(:salesforce_customer, integration:, customer:) }
      let(:integration) { create(:salesforce_integration, organization:) }
      let(:customer) { create(:customer, organization:) }

      before { integration_customer }

      it "returns true" do
        expect(method_call).to eq(true)
      end

      context "when the invoice is self-billed" do
        let(:invoice) { create(:invoice, customer:, organization:, status: :finalized, self_billed: true) }

        it "returns false" do
          expect(method_call).to eq(false)
        end
      end
    end

    context "without integration salesforce customer" do
      let(:customer) { create(:customer, organization:) }

      it "returns false" do
        expect(method_call).to eq(false)
      end
    end
  end

  describe "#should_sync_hubspot_invoice?" do
    subject(:method_call) { invoice.should_sync_hubspot_invoice? }

    let(:invoice) { create(:invoice, customer:, organization:, status:) }

    context "when invoice is not finalized" do
      let(:status) { %i[draft generating voided].sample }

      context "without integration customer" do
        let(:customer) { create(:customer, organization:) }

        it "returns false" do
          expect(method_call).to eq(false)
        end
      end

      context "with integration hubspot customer" do
        let(:integration_customer) { create(:hubspot_customer, integration:, customer:) }
        let(:integration) { create(:hubspot_integration, organization:, sync_invoices:) }
        let(:customer) { create(:customer, organization:) }

        before { integration_customer }

        context "when sync invoices is true" do
          let(:sync_invoices) { true }

          it "returns false" do
            expect(method_call).to eq(false)
          end
        end

        context "when sync invoices is false" do
          let(:sync_invoices) { false }

          it "returns false" do
            expect(method_call).to eq(false)
          end
        end
      end
    end

    context "when invoice is finalized" do
      let(:status) { :finalized }

      context "without integration customer" do
        let(:customer) { create(:customer, organization:) }

        it "returns false" do
          expect(method_call).to eq(false)
        end
      end

      context "with integration hubspot customer" do
        let(:integration_customer) { create(:hubspot_customer, integration:, customer:) }
        let(:integration) { create(:hubspot_integration, organization:, sync_invoices:) }
        let(:customer) { create(:customer, organization:) }

        before { integration_customer }

        context "when sync invoices is true" do
          let(:sync_invoices) { true }

          it "returns true" do
            expect(method_call).to eq(true)
          end
        end

        context "when sync invoices is false" do
          let(:sync_invoices) { false }

          it "returns false" do
            expect(method_call).to eq(false)
          end
        end

        context "when invoice is self_billed" do
          let(:invoice) { create(:invoice, customer:, organization:, status:, self_billed: true) }
          let(:sync_invoices) { true }

          it "returns false" do
            expect(method_call).to eq(false)
          end
        end
      end
    end
  end

  describe "#should_update_hubspot_invoice?" do
    subject(:method_call) { invoice.should_update_hubspot_invoice? }

    let(:invoice) { create(:invoice, customer:, organization:, status:) }

    context "when invoice is not finalized" do
      let(:status) { %i[draft generating voided].sample }

      context "without integration customer" do
        let(:customer) { create(:customer, organization:) }

        it "returns false" do
          expect(method_call).to eq(false)
        end
      end

      context "with integration hubpot customer" do
        let(:integration_customer) { create(:hubspot_customer, integration:, customer:) }
        let(:integration) { create(:hubspot_integration, organization:, sync_invoices:) }
        let(:customer) { create(:customer, organization:) }

        before { integration_customer }

        context "when sync invoices is true" do
          let(:sync_invoices) { true }

          it "returns true" do
            expect(method_call).to eq(true)
          end

          context "when invoice is self_billed" do
            let(:invoice) { create(:invoice, customer:, organization:, status:, self_billed: true) }

            it "returns false" do
              expect(method_call).to eq(false)
            end
          end
        end

        context "when sync invoices is false" do
          let(:sync_invoices) { false }

          it "returns false" do
            expect(method_call).to eq(false)
          end
        end
      end
    end

    context "when invoice is finalized" do
      let(:status) { :finalized }

      context "without integration customer" do
        let(:customer) { create(:customer, organization:) }

        it "returns false" do
          expect(method_call).to eq(false)
        end
      end

      context "with integration hubspot customer" do
        let(:integration_customer) { create(:hubspot_customer, integration:, customer:) }
        let(:integration) { create(:hubspot_integration, organization:, sync_invoices:) }
        let(:customer) { create(:customer, organization:) }

        before { integration_customer }

        context "when sync invoices is true" do
          let(:sync_invoices) { true }

          it "returns true" do
            expect(method_call).to eq(true)
          end

          context "when invoice is self_billed" do
            let(:invoice) { create(:invoice, customer:, organization:, status:, self_billed: true) }

            it "returns false" do
              expect(method_call).to eq(false)
            end
          end
        end

        context "when sync invoices is false" do
          let(:sync_invoices) { false }

          it "returns false" do
            expect(method_call).to eq(false)
          end
        end
      end
    end
  end

  describe "number" do
    let(:organization) { create(:organization, name: "ACME Corporation") }
    let(:billing_entity) { create(:billing_entity, organization:, name: "LAGO") }
    let(:customer) { create(:customer, organization:, billing_entity:) }
    let(:subscription) { create(:subscription, organization:, customer:) }
    let(:invoice) { build(:invoice, customer:, organization:, billing_entity:, billing_entity_sequential_id: nil, status: :generating) }

    it "generates the invoice number" do
      invoice.save!
      invoice.finalized!
      billing_entity_id_substring = billing_entity.id.last(4).upcase

      expect(invoice.number).to eq("LAG-#{billing_entity_id_substring}-001-001")
    end

    context "with billing entity numbering" do
      let(:billing_entity) { create(:billing_entity, organization:, name: "lago", document_numbering: "per_billing_entity") }

      it "scopes the billing_entity_sequential_id to the billing entity and month" do
        invoice.save!
        invoice.finalized!
        billing_entity_id_substring = billing_entity.id.last(4).upcase

        expect(invoice.number).to eq("LAG-#{billing_entity_id_substring}-#{Time.now.utc.strftime("%Y%m")}-001")
      end

      context "with existing invoices in current month" do
        let(:created_at) { Time.now.utc }

        before do
          create(:invoice, customer:, billing_entity:, organization:, sequential_id: 4, billing_entity_sequential_id: 14, created_at:)
          create(:invoice, customer:, billing_entity:, organization:, sequential_id: 5, billing_entity_sequential_id: 15, created_at:)
        end

        it "scopes the billing_entity_sequential_id to the billing entity and month" do
          invoice.save!
          invoice.finalized!

          billing_entity_id_substring = billing_entity.id.last(4).upcase

          expect(invoice.number).to eq("LAG-#{billing_entity_id_substring}-#{Time.now.utc.strftime("%Y%m")}-016")
        end

        context "when invoice is self_billed" do
          let(:invoice) { build(:invoice, customer:, organization:, billing_entity:, billing_entity_sequential_id: nil, status: :generating, self_billed: true) }

          it "generates the invoice number based on customer sequence" do
            invoice.customer.update(sequential_id: 27)
            invoice.save!
            invoice.finalized!
            billing_entity_id_substring = billing_entity.id.last(4).upcase

            expect(invoice.number).to eq("LAG-#{billing_entity_id_substring}-027-006")
          end
        end
      end

      context "with existing invoices in previous month" do
        let(:created_at) { Time.now.utc - 1.month }

        before do
          create(:invoice, customer:, billing_entity:, organization:, sequential_id: 4, billing_entity_sequential_id: 14, created_at:)
          create(:invoice, customer:, billing_entity:, organization:, sequential_id: 5, billing_entity_sequential_id: 15, created_at:)
        end

        it "scopes the billing_entity_sequential_id to the billing entity and month" do
          invoice.save!
          invoice.finalized!

          billing_entity_id_substring = billing_entity.id.last(4).upcase

          expect(invoice.number).to eq("LAG-#{billing_entity_id_substring}-#{Time.now.utc.strftime("%Y%m")}-016")
        end
      end

      context "with existing draft invoices that have generated sequential ids" do
        let(:created_at) { Time.now.utc }

        let(:invoice1) do
          create(
            :invoice,
            customer:,
            organization:,
            billing_entity:,
            sequential_id: 4,
            billing_entity_sequential_id: 14,
            created_at:,
            status: :draft,
            number: "LAG-#{billing_entity.id.last(4).upcase}-#{Time.now.utc.strftime("%Y%m")}-014"
          )
        end
        let(:invoice2) do
          create(
            :invoice,
            customer:,
            organization:,
            billing_entity:,
            sequential_id: 5,
            billing_entity_sequential_id: 15,
            created_at:,
            number: "LAG-#{billing_entity.id.last(4).upcase}-#{Time.now.utc.strftime("%Y%m")}-015"
          )
        end

        before do
          invoice1
          invoice2
        end

        it "scopes the billing_entity_sequential_id to the billing entity and month" do
          invoice.save!
          invoice.finalized!

          billing_entity_id_substring = billing_entity.id.last(4).upcase

          expect(invoice.number).to eq("LAG-#{billing_entity_id_substring}-#{Time.now.utc.strftime("%Y%m")}-016")

          invoice1.update!(payment_due_date: invoice1.payment_due_date + 1.day)
          invoice2.update!(payment_due_date: invoice2.payment_due_date + 1.day)

          expect(invoice1.reload.number).to eq("LAG-#{billing_entity_id_substring}-#{Time.now.utc.strftime("%Y%m")}-014")
          expect(invoice2.reload.number).to eq("LAG-#{billing_entity_id_substring}-#{Time.now.utc.strftime("%Y%m")}-015")

          invoice1.finalized!

          expect(invoice1.reload.number).to eq("LAG-#{billing_entity_id_substring}-#{Time.now.utc.strftime("%Y%m")}-014")
        end
      end

      context "with existing draft invoices that does not have generated sequential ids" do
        let(:created_at) { Time.now.utc }

        let(:invoice1) do
          create(
            :invoice,
            customer:,
            organization:,
            billing_entity:,
            sequential_id: nil,
            billing_entity_sequential_id: nil,
            created_at:,
            status: :draft,
            number: "LAG-#{billing_entity.id.last(4).upcase}-DRAFT"
          )
        end
        let(:invoice2) do
          create(
            :invoice,
            customer:,
            organization:,
            billing_entity:,
            sequential_id: 4,
            billing_entity_sequential_id: 14,
            created_at:,
            number: "LAG-#{billing_entity.id.last(4).upcase}-#{Time.now.utc.strftime("%Y%m")}-014"
          )
        end

        before do
          invoice1
          invoice2
        end

        it "scopes the billing_entity_sequential_id to the billing entity and month" do
          invoice.save!
          invoice.finalized!

          billing_entity_id_substring = billing_entity.id.last(4).upcase

          expect(invoice.number).to eq("LAG-#{billing_entity_id_substring}-#{Time.now.utc.strftime("%Y%m")}-015")

          invoice1.update!(payment_due_date: invoice1.payment_due_date + 1.day)
          invoice2.update!(payment_due_date: invoice2.payment_due_date + 1.day)

          expect(invoice1.reload.number).to eq("LAG-#{billing_entity_id_substring}-DRAFT")
          expect(invoice2.reload.number).to eq("LAG-#{billing_entity_id_substring}-#{Time.now.utc.strftime("%Y%m")}-014")

          invoice1.finalized!

          expect(invoice1.reload.number).to eq("LAG-#{billing_entity_id_substring}-#{Time.now.utc.strftime("%Y%m")}-016")
        end
      end
    end
  end

  describe "#currency" do
    let(:invoice) { build(:invoice, currency: "JPY") }

    it { expect(invoice.currency).to eq("JPY") }
  end

  describe "#charge_amount" do
    let(:organization) { create(:organization, name: "LAGO") }
    let(:customer) { create(:customer, organization:) }
    let(:subscription) { create(:subscription, organization:, customer:) }
    let(:invoice) { create(:invoice, customer:, organization:) }
    let(:fees) { create_list(:fee, 3, invoice:) }

    it "returns the charges amount" do
      expect(invoice.charge_amount.to_s).to eq("0.00")
    end
  end

  describe "#fee_total_amount_cents" do
    let(:organization) { create(:organization, name: "LAGO") }
    let(:customer) { create(:customer, organization:) }
    let(:invoice) { create(:invoice, customer:, organization:) }

    it "returns the fee amount vat included" do
      create(:fee, invoice:, amount_cents: 100, taxes_rate: 20)
      create(:fee, invoice:, amount_cents: 133, taxes_rate: 20)

      expect(invoice.fee_total_amount_cents).to eq(120 + 160)
    end
  end

  describe "#subscription_amount" do
    let(:organization) { create(:organization, name: "LAGO") }
    let(:customer) { create(:customer, organization:) }
    let(:subscription) { create(:subscription, organization:, customer:) }
    let(:invoice) { create(:invoice, customer:, organization:) }
    let(:fees) { create_list(:fee, 2, invoice:) }

    it "returns the subscriptions amount" do
      create(:fee, invoice:, amount_cents: 200)
      create(:fee, invoice:, amount_cents: 100)
      create(:charge_fee, invoice:, charge_id: create(:standard_charge).id)

      expect(invoice.subscription_amount.to_s).to eq("3.00")
    end
  end

  describe "#invoice_subscription" do
    let(:invoice_subscription) { create(:invoice_subscription) }

    it "returns the invoice_subscription for the given subscription id" do
      invoice = invoice_subscription.invoice
      subscription = invoice_subscription.subscription

      expect(invoice.invoice_subscription(subscription.id)).to eq(invoice_subscription)
    end
  end

  describe "#subscription_fees" do
    let(:invoice_subscription) { create(:invoice_subscription) }

    it "returns the fees of the corresponding invoice_subscription" do
      invoice = invoice_subscription.invoice
      subscription = invoice_subscription.subscription
      fee = create(:fee, subscription_id: subscription.id, invoice_id: invoice.id)

      expect(invoice.subscription_fees(subscription.id)).to eq([fee])
    end
  end

  describe "#existing_fees_in_interval?" do
    let(:invoice_subscription) { create(:invoice_subscription) }
    let(:invoice) { invoice_subscription.invoice }
    let(:subscription) { invoice_subscription.subscription }
    let(:billable_metric) { create(:sum_billable_metric, organization: subscription.organization) }
    let(:charge) { create(:standard_charge, plan: subscription.plan, billable_metric:, pay_in_advance: false) }
    let(:fee) { create(:charge_fee, subscription:, invoice:, charge:, units: 1) }

    before { fee }

    it "returns true" do
      expect(invoice.existing_fees_in_interval?(subscription_id: subscription.id)).to eq(true)
    end

    context "when charges are in advance" do
      let(:charge) { create(:standard_charge, plan: subscription.plan, billable_metric:, pay_in_advance: true) }

      it "returns false" do
        expect(invoice.existing_fees_in_interval?(subscription_id: subscription.id)).to eq(false)
      end

      context "with charge_in_advance set to true" do
        it "returns true" do
          expect(invoice.existing_fees_in_interval?(subscription_id: subscription.id, charge_in_advance: true))
            .to eq(true)
        end
      end
    end

    context "when unit number iz zero" do
      let(:fee) { create(:charge_fee, subscription:, invoice:, charge:, units: 0) }

      it "returns false" do
        expect(invoice.existing_fees_in_interval?(subscription_id: subscription.id)).to eq(false)
      end
    end
  end

  describe "#recurring_fees" do
    let(:invoice_subscription) { create(:invoice_subscription) }
    let(:invoice) { invoice_subscription.invoice }
    let(:subscription) { invoice_subscription.subscription }
    let(:billable_metric) { create(:sum_billable_metric, organization: subscription.organization, recurring: true) }
    let(:charge) { create(:standard_charge, plan: subscription.plan, billable_metric:, pay_in_advance: false) }
    let(:fee) { create(:charge_fee, subscription:, invoice:, charge:) }

    it "returns the fees of the corresponding invoice_subscription" do
      expect(invoice.recurring_fees(subscription.id)).to eq([fee])
    end

    context "when charge is pay_in_advance" do
      let(:charge) { create(:standard_charge, plan: subscription.plan, billable_metric:, pay_in_advance: true) }

      it "returns the fees of the corresponding invoice_subscription" do
        expect(invoice.recurring_fees(subscription.id)).to eq([])
      end
    end
  end

  describe "#recurring_breakdown" do
    let(:invoice_subscription) { create(:invoice_subscription) }
    let(:invoice) { invoice_subscription.invoice }
    let(:subscription) { invoice_subscription.subscription }
    let(:billable_metric) { create(:sum_billable_metric, organization: subscription.organization, recurring: true) }
    let(:charge) { create(:standard_charge, plan: subscription.plan, billable_metric:, pay_in_advance: false) }
    let(:fee) { create(:charge_fee, subscription:, invoice:, charge:) }

    it "returns the fees of the corresponding invoice_subscription" do
      expect(invoice.recurring_breakdown(fee)).to eq([])
    end

    context "with charge filter" do
      let(:charge_filter) { create(:charge_filter, charge:) }

      before { fee.update(charge_filter:) }

      it "returns the fees of the corresponding invoice_subscription" do
        expect(invoice.recurring_breakdown(fee)).to eq([])
      end
    end
  end

  describe "#document_invoice_name" do
    let(:organization) { create(:organization, name: "LAGO", country: "FR") }
    let(:customer) { create(:customer, organization:) }
    let(:invoice) { create(:invoice, customer:, organization:) }

    it "returns the correct name for EU country" do
      expect(invoice.document_invoice_name).to eq("Invoice")
    end

    context "when invoice is self billed" do
      let(:invoice) { create(:invoice, :self_billed, customer:, organization:) }

      it "returns the correct name for EU country" do
        expect(invoice.document_invoice_name).to eq("Self-billing invoice")
      end
    end

    context "when organization country is Australia" do
      let(:organization) { create(:organization, name: "LAGO", country: "AU") }

      it "returns the correct name that includes keyword tax" do
        expect(invoice.document_invoice_name).to eq("Tax invoice")
      end
    end

    context "when the organization country is in TAX_INVOICE_LABEL_COUNTRIES" do
      let(:country) { Invoice::TAX_INVOICE_LABEL_COUNTRIES.sample }
      let(:organization) { create(:organization, name: "LAGO", country:) }

      it "returns the correct tax invoice name" do
        expect(invoice.document_invoice_name).to eq(I18n.t("invoice.document_tax_name"))
      end
    end

    context "when it is credit invoice" do
      let(:invoice) { create(:invoice, customer:, organization:, invoice_type: :credit) }

      it "returns the correct name for EU country" do
        expect(invoice.document_invoice_name).to eq("Advance invoice")
      end
    end
  end

  describe "#charge_pay_in_advance_proration_range" do
    let(:invoice_subscription) { create(:invoice_subscription, subscription:) }
    let(:invoice) { invoice_subscription.invoice }
    let(:subscription) { create(:subscription, started_at: timestamp - 1.year) }
    let(:timestamp) { DateTime.parse("2023-07-25 00:00:00 UTC") }
    let(:event) { create(:event, subscription_id: subscription.id, timestamp:) }
    let(:billable_metric) { create(:sum_billable_metric, organization: subscription.organization, recurring: true) }
    let(:fee) { create(:charge_fee, subscription:, invoice:, charge:, pay_in_advance_event_id: event.id, pay_in_advance_event_transaction_id: event.transaction_id) }
    let(:charge) do
      create(:standard_charge, plan: subscription.plan, billable_metric:, pay_in_advance: true, prorated: true)
    end

    it "returns the fees of the corresponding invoice_subscription" do
      expect(invoice.charge_pay_in_advance_proration_range(fee, event.timestamp)).to include(
        period_duration: 31,
        number_of_days: 7
      )
    end
  end

  describe "#voidable?" do
    subject(:voidable) { invoice.voidable? }

    context "when payment disputed was lost" do
      let(:payment_dispute_lost_at) { DateTime.current - 1.day }

      context "when invoice has a voided credit note" do
        let(:invoice) { create(:invoice, status:, payment_status:, payment_dispute_lost_at:) }

        before { create(:credit_note, credit_status: :voided, invoice:) }

        context "when invoice is finalized" do
          let(:status) { :finalized }

          context "when invoice is payment_pending" do
            let(:payment_status) { :pending }

            it "returns false" do
              expect(voidable).to be false
            end
          end

          context "when invoice is payment_failed" do
            let(:payment_status) { :failed }

            it "returns false" do
              expect(voidable).to be false
            end
          end

          context "when invoice is payment_succeeded" do
            let(:payment_status) { :succeeded }

            it "returns false" do
              expect(voidable).to be false
            end
          end
        end
      end

      context "when invoice has a non-voided credit note" do
        let(:invoice) { create(:invoice, status:, payment_status:, payment_dispute_lost_at:) }

        before { create(:credit_note, invoice:) }

        context "when invoice is finalized" do
          let(:status) { :finalized }

          context "when invoice is payment_pending" do
            let(:payment_status) { :pending }

            it "returns false" do
              expect(voidable).to be false
            end
          end

          context "when invoice is payment_failed" do
            let(:payment_status) { :failed }

            it "returns false" do
              expect(voidable).to be false
            end
          end

          context "when invoice is payment_succeeded" do
            let(:payment_status) { :succeeded }

            it "returns false" do
              expect(voidable).to be false
            end
          end
        end
      end

      context "when invoice has no credit notes" do
        let(:invoice) { build_stubbed(:invoice, status:, payment_status:, payment_dispute_lost_at:) }

        context "when invoice is not finalized" do
          let(:status) { :draft }

          context "when invoice is payment_pending" do
            let(:payment_status) { :pending }

            it "returns false" do
              expect(voidable).to be false
            end
          end

          context "when invoice is payment_failed" do
            let(:payment_status) { :failed }

            it "returns false" do
              expect(voidable).to be false
            end
          end

          context "when invoice is payment_succeeded" do
            let(:payment_status) { :succeeded }

            it "returns false" do
              expect(voidable).to be false
            end
          end
        end

        context "when invoice is finalized" do
          let(:status) { :finalized }

          context "when invoice is payment_pending" do
            let(:payment_status) { :pending }

            it "returns false" do
              expect(voidable).to be false
            end
          end

          context "when invoice is payment_failed" do
            let(:payment_status) { :failed }

            it "returns false" do
              expect(voidable).to be false
            end
          end

          context "when invoice is payment_succeeded" do
            let(:payment_status) { :succeeded }

            it "returns false" do
              expect(voidable).to be false
            end
          end
        end
      end
    end

    context "when payment is not disputed" do
      let(:payment_dispute_lost_at) { nil }

      context "when invoice has a voided credit note" do
        let(:invoice) { create(:invoice, status:, payment_status:, payment_dispute_lost_at:, total_paid_amount_cents:) }

        before { create(:credit_note, credit_status: :voided, invoice:) }

        context "when invoice is not finalized" do
          let(:status) { [:draft, :voided].sample }

          context "when invoice is payment_pending" do
            let(:payment_status) { :pending }

            context "when total paid amount is zero" do
              let(:total_paid_amount_cents) { 0 }

              it "returns false" do
                expect(voidable).to be false
              end
            end

            context "when total paid amount is not zero" do
              let(:total_paid_amount_cents) { 1 }

              it "returns false" do
                expect(voidable).to be false
              end
            end
          end

          context "when invoice is payment_failed" do
            let(:payment_status) { :failed }

            context "when total paid amount is zero" do
              let(:total_paid_amount_cents) { 0 }

              it "returns false" do
                expect(voidable).to be false
              end
            end

            context "when total paid amount is not zero" do
              let(:total_paid_amount_cents) { 1 }

              it "returns false" do
                expect(voidable).to be false
              end
            end
          end

          context "when invoice is payment_succeeded" do
            let(:payment_status) { :succeeded }

            context "when total paid amount is zero" do
              let(:total_paid_amount_cents) { 0 }

              it "returns false" do
                expect(voidable).to be false
              end
            end

            context "when total paid amount is not zero" do
              let(:total_paid_amount_cents) { 1 }

              it "returns false" do
                expect(voidable).to be false
              end
            end
          end
        end

        context "when invoice is finalized" do
          let(:status) { :finalized }

          context "when invoice is payment_pending" do
            let(:payment_status) { :pending }

            context "when total paid amount is zero" do
              let(:total_paid_amount_cents) { 0 }

              it "returns true" do
                expect(voidable).to be true
              end
            end

            context "when total paid amount is not zero" do
              let(:total_paid_amount_cents) { 1 }

              it "returns false" do
                expect(voidable).to be false
              end
            end
          end

          context "when invoice is payment_failed" do
            let(:payment_status) { :failed }

            context "when total paid amount is zero" do
              let(:total_paid_amount_cents) { 0 }

              it "returns true" do
                expect(voidable).to be true
              end
            end

            context "when total paid amount is not zero" do
              let(:total_paid_amount_cents) { 1 }

              it "returns false" do
                expect(voidable).to be false
              end
            end
          end

          context "when invoice is payment_succeeded" do
            let(:payment_status) { :succeeded }

            context "when total paid amount is zero" do
              let(:total_paid_amount_cents) { 0 }

              it "returns false" do
                expect(voidable).to be false
              end
            end

            context "when total paid amount is not zero" do
              let(:total_paid_amount_cents) { 1 }

              it "returns false" do
                expect(voidable).to be false
              end
            end
          end
        end
      end

      context "when invoice has a non-voided credit note" do
        let(:invoice) { create(:invoice, status:, payment_status:, payment_dispute_lost_at:) }

        before { create(:credit_note, invoice:) }

        context "when invoice is not finalized" do
          let(:status) { [:draft, :voided].sample }

          context "when invoice is payment_pending" do
            let(:payment_status) { :pending }

            context "when total paid amount is zero" do
              let(:total_paid_amount_cents) { 0 }

              it "returns false" do
                expect(voidable).to be false
              end
            end

            context "when total paid amount is not zero" do
              let(:total_paid_amount_cents) { 1 }

              it "returns false" do
                expect(voidable).to be false
              end
            end
          end

          context "when invoice is payment_failed" do
            let(:payment_status) { :failed }

            context "when total paid amount is zero" do
              let(:total_paid_amount_cents) { 0 }

              it "returns false" do
                expect(voidable).to be false
              end
            end

            context "when total paid amount is not zero" do
              let(:total_paid_amount_cents) { 1 }

              it "returns false" do
                expect(voidable).to be false
              end
            end
          end

          context "when invoice is payment_succeeded" do
            let(:payment_status) { :succeeded }

            context "when total paid amount is zero" do
              let(:total_paid_amount_cents) { 0 }

              it "returns false" do
                expect(voidable).to be false
              end
            end

            context "when total paid amount is not zero" do
              let(:total_paid_amount_cents) { 1 }

              it "returns false" do
                expect(voidable).to be false
              end
            end
          end
        end

        context "when invoice is finalized" do
          let(:status) { :finalized }

          context "when invoice is payment_pending" do
            let(:payment_status) { :pending }

            context "when total paid amount is zero" do
              let(:total_paid_amount_cents) { 0 }

              it "returns false" do
                expect(voidable).to be false
              end
            end

            context "when total paid amount is not zero" do
              let(:total_paid_amount_cents) { 1 }

              it "returns false" do
                expect(voidable).to be false
              end
            end
          end

          context "when invoice is payment_failed" do
            let(:payment_status) { :failed }

            context "when total paid amount is zero" do
              let(:total_paid_amount_cents) { 0 }

              it "returns false" do
                expect(voidable).to be false
              end
            end

            context "when total paid amount is not zero" do
              let(:total_paid_amount_cents) { 1 }

              it "returns false" do
                expect(voidable).to be false
              end
            end
          end

          context "when invoice is payment_succeeded" do
            let(:payment_status) { :succeeded }

            context "when total paid amount is zero" do
              let(:total_paid_amount_cents) { 0 }

              it "returns false" do
                expect(voidable).to be false
              end
            end

            context "when total paid amount is not zero" do
              let(:total_paid_amount_cents) { 1 }

              it "returns false" do
                expect(voidable).to be false
              end
            end
          end
        end
      end

      context "when invoice has no credit notes" do
        let(:invoice) { build_stubbed(:invoice, status:, payment_status:, payment_dispute_lost_at:) }

        context "when invoice is not finalized" do
          let(:status) { [:draft, :voided].sample }

          context "when invoice is payment_pending" do
            let(:payment_status) { :pending }

            it "returns false" do
              expect(voidable).to be false
            end
          end

          context "when invoice is payment_failed" do
            let(:payment_status) { :failed }

            it "returns false" do
              expect(voidable).to be false
            end
          end

          context "when invoice is payment_succeeded" do
            let(:payment_status) { :succeeded }

            it "returns false" do
              expect(voidable).to be false
            end
          end
        end

        context "when invoice is finalized" do
          let(:status) { :finalized }

          context "when invoice is payment_pending" do
            let(:payment_status) { :pending }

            it "returns true" do
              expect(voidable).to be true
            end
          end

          context "when invoice is payment_failed" do
            let(:payment_status) { :failed }

            it "returns true" do
              expect(voidable).to be true
            end
          end

          context "when invoice is payment_succeeded" do
            let(:payment_status) { :succeeded }

            it "returns false" do
              expect(voidable).to be false
            end
          end
        end
      end
    end
  end

  describe "#mark_as_voided!" do
    subject(:force_void_call) { invoice.void! }

    context "when invoice is finalized" do
      let(:invoice) { build(:invoice, status: :finalized, ready_for_payment_processing: true) }

      it "changes the status to voided and disables payment processing" do
        expect { force_void_call }.to change(invoice, :status).from("finalized").to("voided")
          .and change(invoice, :ready_for_payment_processing).from(true).to(false)
      end
    end
  end

  describe "#mark_as_dispute_lost!" do
    subject(:mark_as_dispute_lost_call) { invoice.mark_as_dispute_lost! }

    context "when record is new" do
      let(:invoice) { build(:invoice, payment_dispute_lost_at:, payment_overdue: true) }

      context "when payment is not disputed" do
        let(:payment_dispute_lost_at) { nil }

        it "changes payment disputed lost date" do
          expect { mark_as_dispute_lost_call }.to change(invoice, :payment_dispute_lost_at).from(nil)
            .and change(invoice, :payment_overdue).from(true).to(false)
        end
      end

      context "when payment is disputed" do
        let(:payment_dispute_lost_at) { DateTime.current - 1.day }

        it "does not change payment dispute lost date" do
          expect { mark_as_dispute_lost_call }.not_to change(invoice, :payment_dispute_lost_at)
        end
      end
    end

    context "when record already exists" do
      let(:invoice) { create(:invoice, payment_dispute_lost_at:) }

      context "when payment is not disputed" do
        let(:payment_dispute_lost_at) { nil }

        it "changes payment dispute lost date" do
          expect { mark_as_dispute_lost_call }.to change(invoice, :payment_dispute_lost_at).from(nil)
        end
      end

      context "when payment is disputed" do
        let(:payment_dispute_lost_at) { DateTime.current - 1.day }

        it "does not change payment dispute lost date" do
          expect { mark_as_dispute_lost_call }.not_to change(invoice, :payment_dispute_lost_at)
        end
      end
    end
  end

  describe "#available_to_credit_amount_cents" do
    context "with created fee" do
      before do
        invoice_subscription = create(:invoice_subscription, invoice:)
        subscription = invoice_subscription.subscription
        billable_metric = create(:unique_count_billable_metric, organization: subscription.organization)
        charge = create(:standard_charge, plan: subscription.plan, billable_metric:)
        create(:charge_fee, subscription:, invoice:, charge:, amount_cents: 133, taxes_rate: 20)
        invoice.update(fees_amount_cents: 160)
      end

      context "when invoice v1" do
        let(:invoice) { create(:invoice, version_number: 1) }

        it "returns 0" do
          expect(invoice.available_to_credit_amount_cents).to eq(0)
        end
      end

      context "when invoice is credit" do
        let(:invoice) { create(:invoice, :credit) }

        it "returns 160" do
          expect(invoice.available_to_credit_amount_cents).to eq(160)
        end
      end

      context "when draft" do
        let(:invoice) { create(:invoice, :draft) }

        it "returns 0" do
          expect(invoice.available_to_credit_amount_cents).to eq(0)
        end
      end

      it "returns the expected creditable amount in cents" do
        expect(invoice.available_to_credit_amount_cents).to eq(160)
      end
    end

    context "when fees sum is zero" do
      let(:invoice_subscription) { create(:invoice_subscription) }
      let(:invoice) { invoice_subscription.invoice }
      let(:subscription) { invoice_subscription.subscription }
      let(:billable_metric) { create(:unique_count_billable_metric, organization: subscription.organization) }
      let(:charge) { create(:standard_charge, plan: subscription.plan, billable_metric:) }

      before do
        create(:charge_fee, subscription:, invoice:, charge:, amount_cents: 0, taxes_rate: 20)
      end

      it "returns 0" do
        expect(invoice.available_to_credit_amount_cents).to eq(0)
      end
    end

    context "when invoice v3 with coupons" do
      let(:invoice) do
        create(
          :invoice,
          fees_amount_cents: 200,
          coupons_amount_cents: 20,
          progressive_billing_credit_amount_cents:,
          taxes_amount_cents: 36,
          total_amount_cents: 216,
          taxes_rate: 20,
          version_number: 3
        )
      end

      let(:invoice_subscription) { create(:invoice_subscription, invoice:) }
      let(:subscription) { invoice_subscription.subscription }
      let(:billable_metric) do
        create(:unique_count_billable_metric, organization: subscription.organization)
      end
      let(:charge) do
        create(:standard_charge, plan: subscription.plan, billable_metric:)
      end
      let(:fee) do
        create(:charge_fee, subscription:, invoice:, charge:, amount_cents: 200, taxes_rate: 20)
      end

      let(:progressive_billing_credit_amount_cents) { 0 }

      before { fee }

      it "returns the expected creditable amount in cents" do
        expect(invoice.available_to_credit_amount_cents).to eq(216)
      end

      context "with progressive billing credit" do
        let(:progressive_billing_credit_amount_cents) { 2 }

        it "returns the expected creditable amount in cents" do
          expect(invoice.available_to_credit_amount_cents).to eq(214)
        end
      end
    end
  end

  describe ".file_url" do
    before do
      invoice.file.attach(
        io: StringIO.new(File.read(Rails.root.join("spec/fixtures/blank.pdf"))),
        filename: "invoice.pdf",
        content_type: "application/pdf"
      )
    end

    it "returns the file url" do
      file_url = invoice.file_url

      expect(file_url).to be_present
      expect(file_url).to include(ENV["LAGO_API_URL"])
    end
  end

  describe "#creditable_amount_cents" do
    let(:invoice) { create(:invoice, version_number:, status:, payment_status:, fees_amount_cents:, taxes_amount_cents:, coupons_amount_cents:, progressive_billing_credit_amount_cents:) }
    let(:fees_amount_cents) { 1000 }
    let(:taxes_amount_cents) { 200 }
    let(:coupons_amount_cents) { 100 }
    let(:progressive_billing_credit_amount_cents) { 50 }

    before do
      invoice_subscription = create(:invoice_subscription, invoice:)
      subscription = invoice_subscription.subscription
      billable_metric = create(:unique_count_billable_metric, organization: subscription.organization)
      charge = create(:standard_charge, plan: subscription.plan, billable_metric:)
      create(:charge_fee, subscription:, invoice:, charge:, amount_cents: 133, taxes_rate: 20)
      invoice.update(fees_amount_cents: 160)
    end

    context "when version_number is less than CREDIT_NOTES_MIN_VERSION" do
      let(:version_number) { 1 }
      let(:status) { :finalized }
      let(:payment_status) { :succeeded }

      it "returns 0" do
        expect(invoice.creditable_amount_cents).to eq(0)
      end
    end

    context "when invoice is a draft" do
      let(:version_number) { 2 }
      let(:status) { :draft }
      let(:payment_status) { :succeeded }

      it "returns 0" do
        expect(invoice.creditable_amount_cents).to eq(0)
      end
    end

    context "when all conditions are met" do
      let(:version_number) { 2 }
      let(:status) { :finalized }
      let(:payment_status) { :succeeded }

      it "returns the correct creditable amount" do
        expect(invoice.creditable_amount_cents).to eq(160)
      end
    end

    context "when invoice is a credit" do
      let(:invoice) { create(:invoice, :credit, version_number: 2, status: :finalized, payment_status: :succeeded, fees_amount_cents: 1000, taxes_amount_cents: 200, coupons_amount_cents: 100, progressive_billing_credit_amount_cents: 50) }

      it "returns the correct creditable amount" do
        expect(invoice.creditable_amount_cents).to eq(0)
      end
    end
  end

  describe "#refundable_amount_cents" do
    let(:invoice) do
      create(
        :invoice,
        version_number:,
        status:,
        payment_status:,
        prepaid_credit_amount_cents:,
        total_paid_amount_cents:,
        total_amount_cents: 1000
      )
    end

    let(:available_to_credit_amount_cents) { 1000 }
    let(:prepaid_credit_amount_cents) { 200 }
    let(:total_paid_amount_cents) { 900 }

    before do
      allow(invoice).to receive(:available_to_credit_amount_cents).and_return(available_to_credit_amount_cents)
      create(:payment, payable: invoice, amount_cents: 900, status: :succeeded, payable_payment_status: :succeeded)
    end

    context "when version_number is less than CREDIT_NOTES_MIN_VERSION" do
      let(:version_number) { 1 }
      let(:status) { :finalized }
      let(:payment_status) { :succeeded }

      it "returns 0" do
        expect(invoice.refundable_amount_cents).to eq(0)
      end
    end

    context "when invoice is a draft" do
      let(:version_number) { 2 }
      let(:status) { :draft }
      let(:payment_status) { :succeeded }

      it "returns 0" do
        expect(invoice.refundable_amount_cents).to eq(0)
      end
    end

    context "when payment is not succeeded" do
      let(:version_number) { 2 }
      let(:status) { :finalized }
      let(:payment_status) { :pending }

      context "when total amount is equal to paid amount" do
        let(:total_paid_amount_cents) { 1000 }

        it "returns the correct refundable amount" do
          expect(invoice.refundable_amount_cents).to eq(0)
        end
      end

      context "when total amount is not equal to paid amount" do
        it "returns the correct refundable amount" do
          expect(invoice.refundable_amount_cents).to eq(900)
        end
      end
    end

    context "when all conditions are met" do
      let(:version_number) { 2 }
      let(:status) { :finalized }
      let(:payment_status) { :succeeded }

      it "returns the correct refundable amount" do
        expect(invoice.refundable_amount_cents).to eq(900)
      end
    end

    context "when invoice is a credit" do
      let(:invoice) do
        create(
          :invoice,
          :credit,
          version_number: 2,
          status: :finalized,
          payment_status: :succeeded,
          prepaid_credit_amount_cents: 200,
          total_paid_amount_cents: 900
        )
      end
      let(:associated_active_wallet) { create(:wallet, balance_cents: 500) }

      before do
        allow(invoice).to receive(:associated_active_wallet).and_return(associated_active_wallet)
        allow(invoice).to receive(:available_to_credit_amount_cents).and_return(1000)
      end

      it "returns the minimum of refundable amount and wallet balance" do
        expect(invoice.refundable_amount_cents).to eq(500)
      end

      context "when payment is pending" do
        let(:invoice) { create(:invoice, :credit, version_number: 2, status: :finalized, payment_status: :pending, prepaid_credit_amount_cents: 200) }

        it "returns zero" do
          expect(invoice.refundable_amount_cents).to eq(0)
        end
      end
    end
  end

  describe "#associated_active_wallet" do
    context "when invoice is not a credit" do
      let(:wallet) { create(:wallet) }

      before { wallet }

      it "returns nil" do
        expect(invoice.associated_active_wallet).to be_nil
      end
    end

    context "when customer has no active wallet" do
      let(:invoice) { create :invoice, invoice_type: :credit }
      let(:wallet) { create :wallet, status: :terminated }
      let(:wallet_transaction) { create :wallet_transaction, wallet: wallet }
      let(:fee) { create :fee, fee_type: :credit, invoice:, invoiceable: wallet_transaction }

      before { fee }

      it "returns nil" do
        expect(invoice.associated_active_wallet).to be_nil
      end
    end

    context "when customer has an active wallet that is not associated with this invoice" do
      let(:wallet) { create(:wallet, customer: invoice.customer) }

      it "returns nil" do
        expect(invoice.associated_active_wallet).to be_nil
      end
    end

    context "when there is a wallet associated with this credit invoice" do
      let(:wallet) { create(:wallet, customer: invoice.customer) }
      let(:wallet_transaction) { create(:wallet_transaction, wallet: wallet) }
      let(:fee) { create(:fee, fee_type: :credit, invoice:, invoiceable: wallet_transaction) }
      let(:invoice) { create(:invoice, :credit, version_number: 2, status: :finalized, payment_status: :succeeded) }

      before { fee }

      it "returns the wallet" do
        expect(invoice.associated_active_wallet).to eq(wallet)
      end

      context "when wallet is not active" do
        let(:wallet) { create(:wallet, customer: invoice.customer, status: :terminated) }

        it "returns nil" do
          expect(invoice.associated_active_wallet).to be_nil
        end
      end
    end
  end

  describe "#all_charges_have_fees?" do
    let(:invoice) { create(:invoice, :subscription, subscriptions: [subscription]) }
    let(:plan) { create(:plan) }
    let(:subscription) { create(:subscription, plan:) }

    let(:charge1) { create(:standard_charge, plan:) }
    let(:charge2) { create(:standard_charge, plan:) }

    before do
      create(:charge_fee, charge: charge1, invoice:)
      charge2
    end

    it { expect(invoice).not_to be_all_charges_have_fees }

    context "when all charges have fees" do
      before { create(:charge_fee, charge: charge2, invoice:) }

      it { expect(invoice).to be_all_charges_have_fees }
    end

    context "with filters" do
      let(:charge_filter) { create(:charge_filter, charge: charge1) }

      before do
        create(:charge_fee, charge: charge2, invoice:)
        charge_filter
      end

      it { expect(invoice).not_to be_all_charges_have_fees }

      context "when filters have fees" do
        before { create(:charge_fee, charge: charge1, charge_filter:, invoice:) }

        it { expect(invoice).to be_all_charges_have_fees }
      end
    end
  end

  describe "should_apply_provider_tax?" do
    subject { invoice.should_apply_provider_tax? }

    let(:invoice) { create(:invoice, :subscription, subscriptions: [subscription]) }
    let(:plan) { create(:plan) }
    let(:subscription) { create(:subscription, plan:) }
    let(:charge) { create(:standard_charge, plan:) }

    before { charge_fee }

    context "when there are fees with non zero amount" do
      let(:charge_fee) { create(:charge_fee, charge:, invoice:, amount: 100) }

      it { expect(subject).to be true }
    end

    context "when there are no fees" do
      let(:charge_fee) { nil }

      it { expect(subject).to be false }
    end

    context "when fees amount is zero with skip configuration" do
      let(:charge_fee) { create(:charge_fee, charge:, invoice:, amount: 0) }

      before do
        invoice.customer.update!(finalize_zero_amount_invoice: "skip")
      end

      it { expect(subject).to be false }
    end

    context "when fees amount is zero with finalize configuration" do
      let(:charge_fee) { create(:charge_fee, charge:, invoice:, amount: 0) }

      before do
        invoice.customer.update!(finalize_zero_amount_invoice: "finalize")
      end

      it { expect(subject).to be true }
    end
  end
end
