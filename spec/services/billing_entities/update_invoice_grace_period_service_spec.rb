# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingEntities::UpdateInvoiceGracePeriodService, type: :service do
  include ActiveJob::TestHelper
  subject(:update_service) { described_class.new(billing_entity:, grace_period:) }

  let(:billing_entity) { create(:billing_entity) }
  let(:organization) { billing_entity.organization }
  let(:customer) { create(:customer, organization:) }
  let(:grace_period) { 2 }

  describe "#call" do
    # let(:invoice_to_be_finalized) do
    #   create(:invoice, status: :draft, customer:, issuing_date: DateTime.parse("19 Jun 2022").to_date, billing_entity:)
    # end
    #
    # let(:invoice_to_not_be_finalized) do
    #   create(:invoice, status: :draft, customer:, issuing_date: DateTime.parse("21 Jun 2022").to_date, billing_entity:)
    # end
    #
    # before do
    #   invoice_to_be_finalized
    #   invoice_to_not_be_finalized
    #   allow(Invoices::FinalizeJob).to receive(:perform_later)
    # end

    it "updates invoice grace period on billing_entity" do
      expect { update_service.call }.to change { billing_entity.reload.invoice_grace_period }.from(0).to(2)
    end

    #   TODO: uncomment when we start updating invoices
    #   it "does not finalizes drafts that should be finalized" do
    #     current_date = DateTime.parse("22 Jun 2022")
    #
    #     travel_to(current_date) do
    #       expect {
    #         perform_enqueued_jobs { update_service.call }
    #       }.to change { invoice_to_be_finalized.reload.issuing_date }.to(DateTime.parse("21 Jun 2022"))
    #       expect(Invoices::FinalizeJob).not_to have_received(:perform_later).with(invoice_to_be_finalized)
    #       expect(invoice_to_be_finalized.reload.status).to eq("draft")
    #     end
    #   end
    #
    #   it "updates issuing_date and payment_due_date on draft invoices" do
    #     current_date = DateTime.parse("22 Jun 2022")
    #
    #     travel_to(current_date) do
    #       expect {
    #         perform_enqueued_jobs { update_service.call }
    #       }.to change { invoice_to_not_be_finalized.reload.issuing_date }
    #         .to(DateTime.parse("23 Jun 2022"))
    #         .and change { invoice_to_not_be_finalized.reload.payment_due_date }
    #         .to(DateTime.parse("23 Jun 2022"))
    #         .and change { invoice_to_be_finalized.reload.issuing_date }
    #         .to(DateTime.parse("21 Jun 2022"))
    #         .and change { invoice_to_not_be_finalized.reload.payment_due_date }
    #         .to(DateTime.parse("23 Jun 2022"))
    #     end
    #   end
    #
    #   context "when customer has net_payment_term" do
    #     let(:customer) { create(:customer, organization:, net_payment_term: 3, billing_entity:) }
    #
    #     it "updates issuing_date on draft invoices" do
    #       current_date = DateTime.parse("22 Jun 2022")
    #
    #       travel_to(current_date) do
    #         expect { perform_enqueued_jobs { update_service.call } }.to change { invoice_to_not_be_finalized.reload.issuing_date }
    #           .to(DateTime.parse("23 Jun 2022"))
    #           .and change { invoice_to_not_be_finalized.reload.payment_due_date }
    #           .to(DateTime.parse("26 Jun 2022"))
    #       end
    #     end
    #   end
    #
    #   context "when grace_period is the same as the current one" do
    #     let(:grace_period) { billing_entity.invoice_grace_period }
    #
    #     it "does not finalize any draft invoices" do
    #       current_date = DateTime.parse("22 Jun 2022")
    #
    #       travel_to(current_date) do
    #         update_service.call
    #
    #         expect(Invoices::FinalizeJob).not_to have_received(:perform_later)
    #       end
    #     end
    #
    #     it "does not update issuing_date on draft invoices" do
    #       current_date = DateTime.parse("22 Jun 2022")
    #
    #       travel_to(current_date) do
    #         expect { update_service.call }.not_to change { invoice_to_not_be_finalized.reload.issuing_date }
    #       end
    #     end
    #   end
  end
end
