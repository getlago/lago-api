# frozen_string_literal: true

require "rails_helper"

RSpec.describe Customers::RefreshInvoicesSearchTermsJob do
  subject(:perform_job) { described_class.perform_now(customer_id) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:customer_id) { customer.id }

  let(:refresh_service) { instance_double(Customers::RefreshInvoicesSearchTermsService) }

  before do
    allow(Customers::RefreshInvoicesSearchTermsService).to receive(:call!).and_return(BaseResult.new)
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
