# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invoices::SearchIndexJob do
  before_all do
    create_default(:organization)
    create_default(:customer)
  end

  subject(:perform) { described_class.perform_now(invoice_id) }

  let_it_be(:invoice) { create(:invoice) }

  before do
    allow(Invoices::Search::IndexService).to receive(:call!)
    allow(Invoices::Search::RemoveFromIndexService).to receive(:call!)
  end

  it "runs on the meilisearch queue" do
    expect(described_class.new.queue_name).to eq("meilisearch")
  end

  context "when the invoice exists" do
    let(:invoice_id) { invoice.id }

    it "indexes the invoice" do
      perform

      expect(Invoices::Search::IndexService).to have_received(:call!).with(invoice:)
    end
  end

  context "when the invoice does not exist" do
    let(:invoice_id) { SecureRandom.uuid }

    it "removes the invoice from the index" do
      perform

      expect(Invoices::Search::RemoveFromIndexService).to have_received(:call!).with(invoice_id:)
    end
  end

  describe "retry_on" do
    let(:invoice_id) { invoice.id }

    [
      Meilisearch::CommunicationError.new("Connection refused"),
      Meilisearch::ApiError.new(408, "Request Timeout", ""),
      Meilisearch::TimeoutError.new("Net::ReadTimeout"),
      Errno::ECONNRESET.new,
      Errno::ECONNREFUSED.new,
      Errno::EHOSTUNREACH.new,
      Errno::ETIMEDOUT.new,
      HTTParty::UnsupportedURIScheme.new("Unsupported URI scheme"),
      Net::OpenTimeout.new,
      Net::ReadTimeout.new,
      EOFError.new
    ].each do |error|
      error_class = error.class

      context "when a #{error_class.name} error is raised" do
        before do
          allow(Invoices::Search::IndexService).to receive(:call!).and_raise(error)
        end

        it "retries the job" do
          assert_performed_jobs(3, only: [described_class]) do
            expect do
              described_class.perform_later(invoice_id)
            end.to raise_error(error_class)
          end
        end
      end
    end
  end
end
