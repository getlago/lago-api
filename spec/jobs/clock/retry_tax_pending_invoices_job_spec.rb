# frozen_string_literal: true

require "rails_helper"

describe Clock::RetryTaxPendingInvoicesJob, job: true do
  subject { described_class }

  it_behaves_like "a unique job" do
    let(:job_args) { [] }
  end

  describe ".perform" do
    let(:customer) { create(:customer) }
    let!(:tax_pending_invoice) do
      create(:invoice, status: :pending, tax_status: :pending, customer:, organization: customer.organization)
    end

    it "enqueues a tax pull only for pending invoices with pending taxes" do
      tax_succeeded_invoice = create(:invoice, status: :pending, tax_status: :succeeded, customer:, organization: customer.organization)
      finalized_invoice = create(:invoice, status: :finalized, tax_status: :pending, customer:, organization: customer.organization)

      expect do
        described_class.perform_now
      end.to have_enqueued_job(Invoices::ProviderTaxes::PullTaxesAndApplyJob).with(invoice: tax_pending_invoice)
        .and not_have_enqueued_job(Invoices::ProviderTaxes::PullTaxesAndApplyJob).with(invoice: tax_succeeded_invoice)
        .and not_have_enqueued_job(Invoices::ProviderTaxes::PullTaxesAndApplyJob).with(invoice: finalized_invoice)
    end
  end
end
