# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingSegments::ProcessService do
  describe ".call" do
    subject(:result) { described_class.call(customer:) }

    let(:organization) { create(:organization) }
    let(:customer) do
      create(:customer, organization:, currency: "USD", finalize_zero_amount_invoice: customer_finalize_zero_amount_invoice)
    end
    let(:customer_finalize_zero_amount_invoice) { "inherit" }
    let(:contract) { create(:contract, organization:, customer:, consolidate_invoice:, started_at: Time.zone.parse("2026-07-01")) }
    let(:consolidate_invoice) { true }
    let(:product) { create(:product, :fixed, organization:) }
    let(:rate_card) { create(:rate_card, organization:, product:, currency: "USD") }
    let(:contract_rate_card) do
      create(:contract_rate_card, organization:, contract:, rate_card:, units: 5, effective_date: Date.parse("2026-07-01"))
    end
    let(:rate_card_rate) do
      create(:rate_card_rate, organization:, rate_card:, rate_model:, rate_properties:, min_amount_cents:)
    end
    let(:rate_model) { "standard" }
    let(:rate_properties) { {"amount" => "30.00"} }
    let(:rate_override) { create(:rate_override, organization:, rate_properties: {"amount" => "15.00"}) }
    let(:billing_segment_rate_properties) { {"amount" => "15.00"} }
    let(:billing_segment_pricing_unit) { nil }
    let(:billing_segment_proration_ratio) { 1 }
    let(:min_amount_cents) { 0 }

    let!(:billing_segment) do
      create(
        :billing_segment,
        organization:,
        contract:,
        customer:,
        contract_rate_card:,
        rate_card_rate:,
        rate_override:,
        currency: rate_card.currency,
        pricing_unit: billing_segment_pricing_unit,
        rate_properties: billing_segment_rate_properties,
        proration_ratio: billing_segment_proration_ratio,
        billing_at: Time.zone.parse("2026-08-31 23:59:59"),
        cycle_started_at: Time.zone.parse("2026-08-01"),
        started_at: Time.zone.parse("2026-08-01"),
        ended_at: Time.zone.parse("2026-08-31 23:59:59")
      )
    end

    describe "#pending_segments" do
      it "loads the shared rate card once for both association paths" do
        queries = []
        subscriber = ->(_name, _start, _finish, _id, payload) {
          queries << payload[:sql] if /SELECT.*FROM "rate_cards"/i.match?(payload[:sql])
        }

        ActiveRecord::Base.uncached do
          ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
            segment = described_class.new(customer:).send(:pending_segments).sole

            expect(segment.contract_rate_card.rate_card).to equal(segment.rate_card_rate.rate_card)
          end
        end

        expect(queries.size).to eq(1)
      end
    end

    context "with only usage (metered) products" do
      let(:product) { create(:product, organization:) }

      it "leaves segments pending without creating invoices or fees" do
        expect { result }.to not_change(Invoice, :count).and not_change(Fee, :count)

        expect(result).to be_success
        expect(result.invoices).to eq([])
        expect(billing_segment.reload).to have_attributes(status: "pending", invoice_id: nil)
      end
    end

    describe "#invoice_key" do
      subject(:invoice_key) { described_class.new(customer:).send(:invoice_key, billing_segment) }

      it "returns the invoice grouping key" do
        expect(invoice_key).to eq([Date.parse("2026-08-31"), :shared, "USD", customer.billing_entity_id, [nil, "provider"], nil])
      end

      context "when the customer timezone changes the billing date" do
        before do
          customer.update!(timezone: "America/New_York")
          billing_segment.update!(billing_at: Time.zone.parse("2026-09-01 02:00:00"))
        end

        it "uses the customer-local billing date" do
          expect(invoice_key.first).to eq(Date.parse("2026-08-31"))
        end
      end

      context "when the contract opts out of consolidation" do
        let(:consolidate_invoice) { false }

        it "uses the segment id" do
          expect(invoice_key[1]).to eq(billing_segment.id)
        end
      end

      context "when the segment currency differs from the plan currency" do
        let(:rate_card) { create(:rate_card, organization:, product:, currency: "EUR") }

        before { contract.update!(catalog_plan: create(:catalog_plan, organization:, currency: "USD")) }

        it "uses the stored segment currency" do
          expect(invoice_key[2]).to eq("EUR")
        end
      end

      context "when the contract has a billing entity" do
        let(:billing_entity) { create(:billing_entity, organization:) }

        before { contract.update!(billing_entity:) }

        it "uses the contract billing entity" do
          expect(invoice_key[3]).to eq(billing_entity.id)
        end
      end

      context "when the contract has a purchase order number" do
        before { contract.update!(purchase_order_number: "PO-123") }

        it "uses the purchase order number" do
          expect(invoice_key[5]).to eq("PO-123")
        end
      end

      context "when the customer has a default payment method" do
        let!(:payment_method) { create(:payment_method, organization:, customer:, is_default: true) }

        it "uses the resolved default payment method" do
          expect(invoice_key[4]).to eq([payment_method.id, "provider"])
        end
      end

      context "when the contract has an explicit payment method" do
        let(:payment_method) { create(:payment_method, organization:, customer:, is_default: false) }

        before do
          contract.update!(payment_method:, payment_method_type: "provider")
          create(:payment_method, organization:, customer:, is_default: true)
        end

        it "uses the explicit payment method" do
          expect(invoice_key[4]).to eq([payment_method.id, "provider"])
        end
      end

      context "when the contract payment method is manual" do
        before do
          contract.update!(payment_method_type: "manual")
          create(:payment_method, organization:, customer:, is_default: true)
        end

        it "uses the manual payment method key" do
          expect(invoice_key[4]).to eq([nil, "manual"])
        end
      end

      context "when there is no explicit or default payment method" do
        it "uses the contract payment method type without an id" do
          expect(invoice_key[4]).to eq([nil, "provider"])
        end
      end
    end

    it "prices the fee from the snapshotted rate override" do
      rate_override.update!(rate_properties: {"amount" => "20.00"})

      expect(result).to be_success

      fee = result.invoices.sole.fees.sole
      expect(fee).to have_attributes(amount_cents: 7_500, unit_amount_cents: 1_500, precise_unit_amount: 15,
        rate_card_rate:, rate_override:)
    end

    it "links planless contracts through segments, without subscriptions" do
      expect { result }.not_to change(InvoiceSubscription, :count)

      invoice = result.invoices.sole.reload
      expect(contract.catalog_plan).to be_nil
      expect(invoice.status).to eq("finalized")
      expect(invoice.billing_segments).to eq([billing_segment])
      expect(invoice.contracts).to eq([contract])
      expect(contract.invoices).to eq([invoice])
      expect(invoice.subscriptions).to be_empty
      expect(invoice.fees.sole).to have_attributes(invoiceable: product, subscription_id: nil)
      expect(billing_segment.reload).to have_attributes(status: "done", invoice:)
    end

    it "does not create duplicate invoices or fees on repeated invocation" do
      invoice = result.invoices.sole

      expect { described_class.call!(customer:) }.to not_change(Invoice, :count).and not_change(Fee, :count)
      expect(billing_segment.reload.invoice).to eq(invoice)
    end

    it "raises a retryable error when the advisory lock cannot be acquired" do
      allow(customer).to receive(:with_advisory_lock).and_return(false)

      expect { result }.to raise_error(BaseLockService::FailedToAcquireLock)
      expect(billing_segment.reload).to have_attributes(status: "pending", invoice_id: nil)
    end

    it "rolls back invoice creation on fee failure and succeeds on retry" do
      allow(BillingSegments::Fees::ComputeService).to receive(:call!).and_raise(ActiveRecord::RecordInvalid)

      expect do
        expect { result }.to raise_error(ActiveRecord::RecordInvalid)
      end.to not_change(Invoice, :count).and not_change(Fee, :count)
      expect(billing_segment.reload).to have_attributes(status: "pending", invoice_id: nil)

      allow(BillingSegments::Fees::ComputeService).to receive(:call!).and_call_original
      expect(described_class.call!(customer:).invoices.sole.reload.status).to eq("finalized")
    end

    it "propagates finalization failure and reconciles the existing invoice on retry" do
      failure = Invoices::TransitionToFinalStatusService::Result.new.not_found_failure!(resource: "invoice")
      allow(Invoices::TransitionToFinalStatusService).to receive(:call).and_return(failure)

      expect { result }.to raise_error(BaseService::NotFoundFailure)
      invoice = billing_segment.reload.invoice
      expect(billing_segment.status).to eq("done")
      expect(invoice.status).to eq("generating")

      allow(Invoices::TransitionToFinalStatusService).to receive(:call).and_call_original
      expect { described_class.call!(customer:) }.to not_change(Invoice, :count).and not_change(Fee, :count)
      expect(invoice.reload.status).to eq("finalized")
    end

    it "does not process another customer's pending segments or generating invoices" do
      other_segment = create(:billing_segment, organization:)
      other_invoice = create(:invoice, :generating, organization:, customer: other_segment.customer)
      other_done_segment = create(:billing_segment, organization:, customer: other_segment.customer, status: :done, invoice: other_invoice)

      expect(result).to be_success
      expect(other_segment.reload).to have_attributes(status: "pending", invoice_id: nil)
      expect(other_done_segment.reload.invoice).to eq(other_invoice)
      expect(other_invoice.reload.status).to eq("generating")
    end

    context "with a fractional unit amount and tax" do
      let(:contract_rate_card) do
        create(:contract_rate_card, organization:, contract:, rate_card:, units: 3, effective_date: Date.parse("2026-07-01"))
      end
      let(:rate_override) { nil }
      let(:rate_properties) { {"amount" => "0.3333"} }
      let(:billing_segment_rate_properties) { rate_properties }
      let(:tax) { create(:tax, organization:, rate: 20) }

      before { create(:customer_applied_tax, organization:, customer:, tax:) }

      it "persists precise fee and tax amounts without deriving them from rounded totals" do
        expect(result).to be_success

        fee = result.invoices.sole.fees.sole.reload
        expect(fee).to have_attributes(
          units: 3,
          amount_cents: 100,
          precise_amount_cents: BigDecimal("99.99"),
          unit_amount_cents: 33,
          precise_unit_amount: BigDecimal("0.3333"),
          taxes_amount_cents: 20,
          taxes_precise_amount_cents: BigDecimal("19.998")
        )
        expect(fee.applied_taxes.sole).to have_attributes(
          tax:,
          amount_cents: 20,
          precise_amount_cents: BigDecimal("19.998")
        )
      end
    end

    context "with a unit amount that would round up in cents and tax" do
      let(:contract_rate_card) do
        create(:contract_rate_card, organization:, contract:, rate_card:, units: 3, effective_date: Date.parse("2026-07-01"))
      end
      let(:rate_override) { nil }
      let(:rate_properties) { {"amount" => "0.336"} }
      let(:billing_segment_rate_properties) { rate_properties }
      let(:tax) { create(:tax, organization:, rate: 20) }

      before { create(:customer_applied_tax, organization:, customer:, tax:) }

      it "persists truncated unit cents while preserving precise fee and tax amounts" do
        expect(result).to be_success

        fee = result.invoices.sole.fees.sole.reload
        expect(fee).to have_attributes(
          units: 3,
          amount_cents: 101,
          precise_amount_cents: BigDecimal("100.8"),
          unit_amount_cents: 33,
          precise_unit_amount: BigDecimal("0.336"),
          taxes_amount_cents: 20,
          taxes_precise_amount_cents: BigDecimal("20.16")
        )
        expect(fee.applied_taxes.sole).to have_attributes(
          tax:,
          amount_cents: 20,
          precise_amount_cents: BigDecimal("20.16")
        )
      end
    end

    context "with a minimum amount above the fee amount" do
      let(:rate_override) { nil }
      let(:billing_segment_rate_properties) { {"amount" => "10.00"} }
      let(:min_amount_cents) { 10_000 }

      it "persists the fee and its true-up fee" do
        expect(result).to be_success
        invoice = result.invoices.sole
        fee, true_up_fee = invoice.fees.order(:created_at)
        expect(invoice.total_amount_cents).to eq(10_000)
        expect(fee.amount_cents).to eq(5_000)
        expect(true_up_fee).to have_attributes(amount_cents: 5_000, true_up_parent_fee_id: fee.id)
      end
    end

    context "with a mid-day rate change in a June cycle" do
      let(:customer) { create(:customer, organization:, currency: "USD", timezone: "UTC") }
      let(:contract) { create(:contract, organization:, customer:, consolidate_invoice:, started_at: Time.utc(2026, 6, 1)) }
      let(:contract_rate_card) do
        create(:contract_rate_card, organization:, contract:, rate_card:, units: 5, effective_date: Date.new(2026, 6, 1))
      end
      let(:min_amount_cents) { 30_000 }
      let(:rate_override) { nil }
      let(:cycle_start) { Time.utc(2026, 6, 1) }
      let(:cycle_end) { Time.utc(2026, 7, 1) }
      let(:rate_change_at) { Time.utc(2026, 6, 16, 9, 30) }
      let!(:billing_segment) do
        build(:billing_segment, organization:, customer:, contract:, contract_rate_card:, rate_card_rate:,
          currency: "USD", rate_properties:, billing_at: cycle_end, cycle_started_at: cycle_start,
          started_at: cycle_start, ended_at: BillingSegment.inclusive_end(rate_change_at)).tap do |segment|
          segment.proration_ratio = segment.duration_in_days.to_d / 30
          segment.save!
        end
      end
      let!(:second_segment) do
        override = create(:rate_override, organization:, rate_properties: {"amount" => "45.00"}, min_amount_cents:)
        build(:billing_segment, organization:, customer:, contract:, contract_rate_card:, rate_card_rate:,
          rate_override: override, currency: "USD", rate_properties: override.rate_properties,
          billing_at: cycle_end, cycle_started_at: cycle_start, started_at: rate_change_at,
          ended_at: BillingSegment.inclusive_end(cycle_end)).tap do |segment|
          segment.proration_ratio = segment.duration_in_days.to_d / 30
          segment.save!
        end
      end

      it "bills each segment's base fee and prorated minimum without counting June 16 twice" do
        segments = [billing_segment.reload, second_segment.reload]
        expect(segments.map(&:duration_in_days)).to eq([16, 14])
        expect(segments.sum(&:duration_in_days)).to eq(30)
        expect(segments.first.prorated_min_amount_cents).to be_within(0.00001).of(16_000)
        expect(segments.last.prorated_min_amount_cents).to be_within(0.00001).of(14_000)

        expect(result).to be_success
        invoice = result.invoices.sole.reload
        expect(invoice).to have_attributes(status: "finalized", total_amount_cents: 30_000)
        expect(invoice.fees.count).to eq(4)

        [[segments.first, 8_000, 8_000, 16], [segments.last, 10_500, 3_500, 21]].each do |segment, base_cents, true_up_cents, unit_amount|
          fees = invoice.fees.where("properties ->> 'billing_segment_id' = ?", segment.id)
          fee = fees.find_by!(true_up_parent_fee_id: nil)
          true_up_fee = fees.where.not(true_up_parent_fee_id: nil).sole

          expect(fee).to have_attributes(amount_cents: base_cents, units: 5)
          expect(fee.precise_unit_amount).to be_within(0.00001).of(unit_amount)
          expect(fee.precise_amount_cents).to be_within(0.00001).of(base_cents)
          expect(true_up_fee).to have_attributes(amount_cents: true_up_cents, units: 1, true_up_parent_fee_id: fee.id)
          expect(true_up_fee.precise_amount_cents).to be_within(0.00001).of(true_up_cents)
          expect(fees.sum(:amount_cents)).to eq(segment.prorated_min_amount_cents.round)
          expect(segment.reload).to have_attributes(status: "done", invoice:)
        end
      end
    end

    context "with a fixed product graduated rate" do
      let(:rate_card) { create(:rate_card, organization:, currency: "USD", product: create(:product, :fixed, organization:)) }
      let(:rate_model) { "graduated" }
      let(:rate_override) { nil }
      let(:rate_properties) do
        {"graduated_ranges" => [
          {"from_value" => 0, "to_value" => 3, "per_unit_amount" => "10.00", "flat_amount" => "0.00"},
          {"from_value" => 4, "to_value" => nil, "per_unit_amount" => "6.00", "flat_amount" => "0.00"}
        ]}
      end
      let(:billing_segment_rate_properties) { rate_properties }

      it "persists the tiered fee on the finalized invoice" do
        expect(result).to be_success
        invoice = result.invoices.sole
        fee = invoice.fees.sole
        expect(invoice.total_amount_cents).to eq(4_200)
        expect(fee).to have_attributes(amount_cents: 4_200, unit_amount_cents: 840, precise_unit_amount: 8.4)
        expect(fee.amount_details["graduated_ranges"].size).to eq(2)
      end
    end

    context "with a fixed product volume rate" do
      let(:rate_card) { create(:rate_card, organization:, currency: "USD", product: create(:product, :fixed, organization:)) }
      let(:rate_model) { "volume" }
      let(:rate_override) { nil }
      let(:rate_properties) do
        {"volume_ranges" => [
          {"from_value" => 0, "to_value" => 3, "per_unit_amount" => "10.00", "flat_amount" => "0.00"},
          {"from_value" => 4, "to_value" => nil, "per_unit_amount" => "6.00", "flat_amount" => "0.00"}
        ]}
      end
      let(:billing_segment_rate_properties) { rate_properties }

      it "persists the tiered fee on the finalized invoice" do
        expect(result).to be_success
        invoice = result.invoices.sole
        fee = invoice.fees.sole
        expect(invoice.total_amount_cents).to eq(3_000)
        expect(fee).to have_attributes(amount_cents: 3_000, unit_amount_cents: 600, precise_unit_amount: 6)
        expect(fee.amount_details["per_unit_total_amount"]).to eq("30.0")
      end
    end

    context "with minimum amounts across rate models" do
      let(:rate_override) { nil }
      let(:min_amount_cents) { 10_000 }

      shared_examples "persists the minimum true-up" do |expected_base_amount_cents|
        it "persists the fee and linked true-up fee" do
          expect(result).to be_success
          invoice = result.invoices.sole
          fee, true_up_fee = invoice.fees.order(:created_at)
          expect(invoice.total_amount_cents).to eq(10_000)
          expect(fee.amount_cents).to eq(expected_base_amount_cents)
          expect(true_up_fee).to have_attributes(amount_cents: 10_000 - expected_base_amount_cents, true_up_parent_fee_id: fee.id)
        end
      end

      context "with a standard rate" do
        let(:rate_properties) { {"amount" => "5.00"} }
        let(:billing_segment_rate_properties) { rate_properties }

        it_behaves_like "persists the minimum true-up", 2_500

        context "when the fee reaches the floor" do
          let(:rate_properties) { {"amount" => "20.00"} }

          it "does not create a true-up fee" do
            expect(result).to be_success
            invoice = result.invoices.sole
            expect(invoice.total_amount_cents).to eq(10_000)
            expect(invoice.fees.sole).to have_attributes(amount_cents: 10_000, true_up_parent_fee_id: nil)
          end
        end

        context "with a prorated period" do
          let(:billing_segment_proration_ratio) { 0.75 }

          it "persists a true-up to the prorated floor" do
            expect(result).to be_success
            invoice = result.invoices.sole
            fee, true_up_fee = invoice.fees.order(:created_at)
            expect(invoice.total_amount_cents).to eq(7_500)
            expect(fee.amount_cents).to eq(1_875)
            expect(true_up_fee).to have_attributes(amount_cents: 5_625, true_up_parent_fee_id: fee.id)
          end
        end
      end

      context "with a graduated rate" do
        let(:rate_model) { "graduated" }
        let(:rate_properties) do
          {"graduated_ranges" => [
            {"from_value" => 0, "to_value" => 3, "per_unit_amount" => "10.00", "flat_amount" => "0.00"},
            {"from_value" => 4, "to_value" => nil, "per_unit_amount" => "6.00", "flat_amount" => "0.00"}
          ]}
        end
        let(:billing_segment_rate_properties) { rate_properties }

        it_behaves_like "persists the minimum true-up", 4_200
      end

      context "with a volume rate" do
        let(:rate_model) { "volume" }
        let(:rate_properties) do
          {"volume_ranges" => [
            {"from_value" => 0, "to_value" => 3, "per_unit_amount" => "10.00", "flat_amount" => "0.00"},
            {"from_value" => 4, "to_value" => nil, "per_unit_amount" => "6.00", "flat_amount" => "0.00"}
          ]}
        end
        let(:billing_segment_rate_properties) { rate_properties }

        it_behaves_like "persists the minimum true-up", 3_000
      end
    end

    context "when a scheduled segment has a pricing unit" do
      let(:pricing_unit) { create(:pricing_unit, organization:, code: "credits", short_name: "cr") }
      let(:rate_card) { create(:rate_card, organization:, product:, currency: "USD", applied_pricing_unit_code: pricing_unit.code) }
      let(:rate_card_rate) do
        create(:rate_card_rate, organization:, rate_card:, rate_properties: {"amount" => "10.00"}, applied_pricing_unit_conversion_rate: 0.5)
      end
      let(:rate_override) { nil }
      let(:billing_segment_rate_properties) { {"amount" => "10.00"} }
      let(:billing_segment_pricing_unit) { pricing_unit }

      it "uses the segment pricing unit to compute the fee" do
        expect(result).to be_success
        fee = result.invoices.sole.fees.sole
        expect(fee.amount_cents).to eq(2_500)
        expect(fee.pricing_unit_usage).to have_attributes(pricing_unit:, amount_cents: 5_000, conversion_rate: 0.5)
      end
    end

    context "with multiple segments due on the same billing date" do
      let(:second_contract) { contract }
      let(:second_rate_card) { create(:rate_card, organization:, product:, currency: "USD") }
      let(:second_contract_rate_card) do
        create(:contract_rate_card, organization:, contract: second_contract, rate_card: second_rate_card, units: 3, effective_date: Date.parse("2026-07-01"))
      end
      let(:second_rate_card_rate) do
        create(:rate_card_rate, organization:, rate_card: second_rate_card, rate_properties: {"amount" => "20.00"})
      end
      let!(:second_segment) do
        create(:billing_segment, organization:, contract: second_contract, customer:,
          contract_rate_card: second_contract_rate_card, rate_card_rate: second_rate_card_rate,
          currency: second_rate_card.currency, rate_properties: {"amount" => "20.00"},
          billing_at: Time.zone.parse("2026-08-31 10:00:00"), cycle_started_at: Time.zone.parse("2026-08-01"),
          started_at: Time.zone.parse("2026-08-01"), ended_at: Time.zone.parse("2026-08-31 23:59:59"))
      end

      it "consolidates same-date segments into one invoice" do
        expect(result).to be_success
        invoice = result.invoices.sole.reload
        expect(invoice.fees.count).to eq(2)
        expect(BillingSegment.where(customer:).distinct.pluck(:invoice_id)).to eq([invoice.id])
      end

      context "when the contract opts out of invoice consolidation" do
        let(:consolidate_invoice) { false }

        it "creates one invoice per segment" do
          expect(result).to be_success
          invoices = result.invoices.map(&:reload)
          expect(invoices.map { |invoice| invoice.fees.count }).to eq([1, 1])
          expect(BillingSegment.where(customer:).pluck(:invoice_id)).to match_array(invoices.map(&:id))
        end
      end

      context "with different contracts" do
        let(:second_contract) { create(:contract, organization:, customer:, consolidate_invoice: true) }

        it "links both contracts to the consolidated invoice" do
          invoice = result.invoices.sole
          expect(invoice.contracts).to match_array([contract, second_contract])
          expect(invoice.billing_segments.pluck(:contract_id)).to match_array([contract.id, second_contract.id])
        end

        shared_examples "splits invoices" do
          it "creates a separate invoice for each grouping key" do
            expect(result).to be_success
            expect(result.invoices.map { |invoice| invoice.fees.count }).to eq([1, 1])
            expect(billing_segment.reload.invoice_id).not_to eq(second_segment.reload.invoice_id)
          end
        end

        context "with different billing dates" do
          before { second_segment.update!(billing_at: Time.zone.parse("2026-09-01")) }

          it_behaves_like "splits invoices"
        end

        context "with different currencies" do
          let(:second_rate_card) { create(:rate_card, organization:, product:, currency: "EUR") }

          it_behaves_like "splits invoices"
        end

        context "with different billing entities" do
          before { second_contract.update!(billing_entity: create(:billing_entity, organization:)) }

          it_behaves_like "splits invoices"
        end

        context "with different payment methods" do
          before { second_contract.update!(payment_method_type: "manual") }

          it_behaves_like "splits invoices"
        end

        context "with different purchase order numbers" do
          before { second_contract.update!(purchase_order_number: "PO-123") }

          it_behaves_like "splits invoices"
        end
      end

      it "rolls back persisted fees if a later fee fails to save" do
        allow(BillingSegments::Fees::ComputeService).to receive(:call!).and_wrap_original do |original, **args|
          computed = original.call(**args)
          if args[:billing_segment].id == second_segment.id
            computed.fee.amount_currency = "invalid"
          end
          computed
        end

        expect do
          expect { result }.to raise_error(ActiveRecord::RecordInvalid)
        end.to not_change(Invoice, :count).and not_change(Fee, :count)
        expect(BillingSegment.where(customer:).pluck(:status, :invoice_id)).to eq([["pending", nil], ["pending", nil]])
      end
    end

    context "with a zero amount segment" do
      let(:rate_override) { nil }
      let(:rate_properties) { {"amount" => "0.00"} }
      let(:billing_segment_rate_properties) { rate_properties }

      context "when zero amount invoices should be skipped" do
        let(:customer_finalize_zero_amount_invoice) { "skip" }

        it "closes the invoice" do
          expect(result).to be_success
          invoice = result.invoices.sole.reload
          expect(invoice.status).to eq("closed")
          expect(invoice.number).to include("DRAFT")
        end
      end

      context "when zero amount invoices should be finalized" do
        let(:customer_finalize_zero_amount_invoice) { "finalize" }

        it "finalizes the invoice" do
          expect(result).to be_success
          invoice = result.invoices.sole.reload
          expect(invoice.status).to eq("finalized")
          expect(invoice.number).not_to include("DRAFT")
        end
      end
    end
  end
end
