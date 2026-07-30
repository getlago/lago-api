# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invoices::CreateAdvanceChargesInvoiceSubscriptionService do
  subject(:create_service) do
    described_class.new(invoice:, timestamp:, subscriptions_with_fees:, all_subscriptions:)
  end

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:, interval: "monthly", pay_in_advance: true) }
  let(:invoice) { create(:invoice, organization:, customer:, invoice_type: :advance_charges, status: :generating) }
  let(:timestamp) { DateTime.new(2025, 2, 1, 10) }

  describe "#call" do
    # The customer re-subscribed with a backdated `subscription_at`, so the active subscription has an
    # earlier `started_at` than the terminated one it replaced, and the terminated one drives the boundaries.
    let(:active_subscription) do
      create(
        :subscription,
        plan:,
        customer:,
        subscription_at: DateTime.new(2024, 3, 1),
        started_at: DateTime.new(2024, 3, 1)
      )
    end

    let(:terminated_subscription) do
      create(
        :subscription,
        plan:,
        customer:,
        external_id: active_subscription.external_id,
        status: :terminated,
        subscription_at: DateTime.new(2024, 3, 15, 10),
        started_at: DateTime.new(2024, 3, 15, 10),
        terminated_at: DateTime.new(2024, 4, 5, 10)
      )
    end

    let(:subscriptions_with_fees) { [terminated_subscription] }
    let(:all_subscriptions) { [terminated_subscription, active_subscription] }

    it "computes the boundaries of the terminated subscription on its own last period" do
      result = create_service.call

      expect(result).to be_success

      invoice_subscription = invoice.invoice_subscriptions.sole
      expect(invoice_subscription.charges_from_datetime).to match_datetime DateTime.new(2024, 4, 1)
      expect(invoice_subscription.charges_to_datetime).to match_datetime DateTime.new(2024, 4, 5, 10)
      expect(invoice_subscription.from_datetime).to match_datetime DateTime.new(2024, 4, 1)
      expect(invoice_subscription.to_datetime).to match_datetime DateTime.new(2024, 4, 5, 10)
      expect(invoice_subscription.invoicing_reason).to eq "in_advance_charge_periodic"
      expect(invoice_subscription.timestamp).to match_datetime timestamp
    end

    context "when the latest subscription is active" do
      let(:active_subscription) do
        create(
          :subscription,
          plan:,
          customer:,
          subscription_at: DateTime.new(2024, 5, 1),
          started_at: DateTime.new(2024, 5, 1)
        )
      end

      let(:subscriptions_with_fees) { [terminated_subscription, active_subscription] }

      it "computes the boundaries on the billed period" do
        result = create_service.call

        expect(result).to be_success
        expect(invoice.invoice_subscriptions.count).to eq(2)

        invoice.invoice_subscriptions.each do |invoice_subscription|
          expect(invoice_subscription.charges_from_datetime).to match_datetime DateTime.new(2025, 1, 1)
          expect(invoice_subscription.charges_to_datetime.to_date).to eq Date.new(2025, 1, 31)
        end
      end
    end

    context "when the boundaries are still invalid" do
      before do
        date_service = instance_double(
          Subscriptions::Dates::MonthlyService,
          charges_from_datetime: DateTime.new(2025, 2, 1),
          charges_to_datetime: DateTime.new(2024, 4, 5, 10)
        )

        allow(Subscriptions::DatesService).to receive(:new_instance).and_return(date_service)
        allow(Rails.logger).to receive(:warn)
      end

      it "does not create any invoice subscription and reports it" do
        result = create_service.call

        expect(result).to be_success
        expect(invoice.invoice_subscriptions).to be_empty
        expect(Rails.logger).to have_received(:warn).with(/skipped: invalid charges boundaries/)
      end
    end

    context "when the subscription has no charges boundaries" do
      before do
        date_service = instance_double(
          Subscriptions::Dates::YearlyService,
          charges_from_datetime: nil,
          charges_to_datetime: nil
        )

        allow(Subscriptions::DatesService).to receive(:new_instance).and_return(date_service)
        allow(Rails.logger).to receive(:warn)
      end

      it "creates the invoice subscription without charges boundaries" do
        result = create_service.call

        expect(result).to be_success

        invoice_subscription = invoice.invoice_subscriptions.sole
        expect(invoice_subscription.charges_from_datetime).to be_nil
        expect(invoice_subscription.charges_to_datetime).to be_nil
        expect(Rails.logger).not_to have_received(:warn)
      end
    end
  end
end
