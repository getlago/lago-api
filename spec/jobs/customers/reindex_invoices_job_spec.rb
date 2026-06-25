# frozen_string_literal: true

require "rails_helper"

RSpec.describe Customers::ReindexInvoicesJob do
  subject(:perform) { described_class.perform_now(customer) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:invoice) { create(:invoice, organization:, customer:) }
  let(:other_invoice) { create(:invoice, organization:) }

  before do
    invoice
    other_invoice
    allow(Invoices::SearchIndexJob).to receive(:perform_later)
  end

  it "enqueues a reindex job for each of the customer's invoices" do
    perform

    expect(Invoices::SearchIndexJob).to have_received(:perform_later).with(invoice.id)
    expect(Invoices::SearchIndexJob).not_to have_received(:perform_later).with(other_invoice.id)
  end
end
