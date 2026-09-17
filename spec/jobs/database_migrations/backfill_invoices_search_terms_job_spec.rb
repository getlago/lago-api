# frozen_string_literal: true

require "rails_helper"

RSpec.describe DatabaseMigrations::BackfillInvoicesSearchTermsJob do
  subject(:perform_job) { described_class.perform_now }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:, name: "Acme Inc") }

  let!(:invoice) { create(:invoice, organization:, customer:, number: "INV-001") }

  before do
    Invoice.where(id: invoice.id).update_all(search_terms: nil) # rubocop:disable Rails/SkipsModelValidations
  end

  it "fills the invoices missing their search terms" do
    perform_job

    expect(invoice.reload.search_terms).to include("INV-001", "Acme Inc")
  end

  it "does not enqueue another batch when the walk is over" do
    expect { perform_job }.not_to have_enqueued_job(described_class)
  end

  context "when the batch is full" do
    before do
      stub_const("#{described_class}::BATCH_SIZE", 1)
      create(:invoice, organization:, customer:, number: "INV-002")
    end

    it "chains to the next batch from the last id" do
      expect { perform_job }.to have_enqueued_job(described_class)
    end
  end

  context "when rows are still missing after a full pass" do
    it "runs a second pass from the start" do
      expect { described_class.perform_now(Invoice.order(:id).last.id, 1) }
        .to have_enqueued_job(described_class).with(nil, 2)
    end
  end

  context "when rows are still missing after the last pass" do
    it "reports instead of looping" do
      allow(Rails.logger).to receive(:error)

      described_class.perform_now(Invoice.order(:id).last.id, described_class::MAX_PASSES)

      expect(Rails.logger).to have_received(:error).with(/still NULL/)
    end
  end

  context "when every invoice already has search terms" do
    before { Invoices::RefreshSearchTermsService.call(invoice:) }

    it "leaves them untouched" do
      expect { perform_job }.not_to change { invoice.reload.search_terms }
    end
  end
end
