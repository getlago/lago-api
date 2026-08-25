# frozen_string_literal: true

require "rails_helper"

RSpec.describe Customers::RefreshInvoicesSearchTermsJob do
  subject(:perform_job) { described_class.perform_now(customer_id) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:customer_id) { customer.id }

  before do
    allow(Customers::RefreshInvoicesSearchTermsService).to receive(:call!).and_return(BaseResult.new)
  end

  it_behaves_like "a unique job" do
    let(:job_args) { [customer.id] }
  end

  describe "unique" do
    it "has unique :until_executing constraint" do
      expect(described_class.lock_strategy_class).to eq(ActiveJob::Uniqueness::Strategies::UntilExecuting)
      expect(described_class.lock_options).to eq(on_conflict: :log)
    end
  end

  it "refreshes the invoices of the customer" do
    perform_job

    expect(Customers::RefreshInvoicesSearchTermsService).to have_received(:call!).with(customer:)
  end

  context "when the customer is discarded" do
    before { customer.discard! }

    it "still refreshes, since discarded customers keep their terms" do
      perform_job

      expect(Customers::RefreshInvoicesSearchTermsService).to have_received(:call!)
    end
  end

  context "when the customer no longer exists" do
    let(:customer_id) { SecureRandom.uuid }

    it "does nothing" do
      perform_job

      expect(Customers::RefreshInvoicesSearchTermsService).not_to have_received(:call!)
    end
  end
end
