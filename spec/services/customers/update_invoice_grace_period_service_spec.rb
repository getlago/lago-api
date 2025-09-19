# frozen_string_literal: true

require "rails_helper"

RSpec.describe Customers::UpdateInvoiceGracePeriodService do
  subject(:update_service) { described_class.new(customer:, grace_period:) }

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization:) }
  let(:grace_period) { 2 }

  describe "#call" do
    let(:invoice_to_be_finalized) do
      create(:invoice, status: :draft, customer:, issuing_date: DateTime.parse("19 Jun 2022").to_date, organization:)
    end

    let(:invoice_to_not_be_finalized) do
      create(:invoice, status: :draft, customer:, issuing_date: DateTime.parse("21 Jun 2022").to_date, organization:)
    end

    before do
      invoice_to_be_finalized
      invoice_to_not_be_finalized
      allow(Invoices::FinalizeJob).to receive(:perform_later)
    end

    it "updates invoice grace period on customer" do
      expect { update_service.call }.to change { customer.reload.invoice_grace_period }.from(nil).to(2)
    end

    it "finalizes corresponding draft invoices" do
      current_date = DateTime.parse("22 Jun 2022")

      travel_to(current_date) do
        result = update_service.call

        expect(result.customer.invoice_grace_period).to eq(2)
        expect(Invoices::FinalizeJob).not_to have_received(:perform_later).with(invoice_to_not_be_finalized)
        expect(Invoices::FinalizeJob).to have_received(:perform_later).with(invoice_to_be_finalized)
      end
    end

    it "updates issuing_date on draft invoices" do
      current_date = DateTime.parse("22 Jun 2022")

      travel_to(current_date) do
        expect { update_service.call }.to change { invoice_to_not_be_finalized.reload.issuing_date }
          .to(DateTime.parse("23 Jun 2022"))
          .and change { invoice_to_not_be_finalized.reload.payment_due_date }
          .to(DateTime.parse("23 Jun 2022"))
      end
    end

    context "when customer has net_payment_term" do
      let(:customer) { create(:customer, organization:, net_payment_term: 3) }

      it "updates issuing_date on draft invoices with payment term" do
        current_date = DateTime.parse("22 Jun 2022")

        travel_to(current_date) do
          expect { update_service.call }.to change { invoice_to_not_be_finalized.reload.issuing_date }
            .to(DateTime.parse("23 Jun 2022"))
            .and change { invoice_to_not_be_finalized.reload.payment_due_date }
            .to(DateTime.parse("26 Jun 2022"))
        end
      end
    end

    context "when grace period is the same" do
      let(:grace_period) { customer.invoice_grace_period }

      it "does not finalize any draft invoices" do
        current_date = DateTime.parse("22 Jun 2022")

        travel_to(current_date) do
          update_service.call

          expect(Invoices::FinalizeJob).not_to have_received(:perform_later)
        end
      end

      it "does not update issuing_date on draft invoices" do
        current_date = DateTime.parse("22 Jun 2022")

        travel_to(current_date) do
          expect { update_service.call }.not_to change { invoice_to_not_be_finalized.reload.issuing_date }
        end
      end
    end

    context "when clearing grace period" do
      before do
        customer.update(invoice_grace_period: 0)
      end

      let(:grace_period) { nil }

      it "clears the grace period" do
        expect { update_service.call }.to change(customer, :invoice_grace_period).from(0).to(nil)
      end
    end
  end
end
