# frozen_string_literal: true

require "rails_helper"

RSpec.describe Webhooks::Invoices::PaymentOverdueService do
  subject(:webhook_service) { described_class.new(object: invoice) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:invoice) { create(:invoice, payment_overdue: true, customer:, organization:) }

  describe ".call" do
    it_behaves_like "creates webhook", "invoice.payment_overdue", "invoice"
    it_behaves_like "sends the catalog invoice on v2"
  end
end
